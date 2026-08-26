# Architecture

## Layering

```
Flutter UI            lib/features/*
      │
Application / Domain  lib/domain/*      pure Dart; no Flutter, no native
      │
Repository interfaces lib/domain/repositories
      │
Data layer            lib/data/*        drift, file system, platform channels
      │
PdfEngine interface   lib/domain/engine
      │
      ├─ PdfrxEngine  lib/engine        PDFium, production
      └─ FakePdfEngine test/fakes        unit tests, no native code
```

## The PdfEngine boundary

`PdfEngine` exposes **no write, save, or export method**. That is not an
oversight — it makes "SP-1 cannot alter a PDF" a property the compiler enforces
rather than a promise in a code review.

It is also a *testing* requirement. PDFium is native code, so anything touching
it needs a simulator or device. CI's Ubuntu and Windows runners have neither.
Routing domain logic through the interface lets unit tests inject
`FakePdfEngine` and run anywhere, which is what makes the 80% business-logic
coverage target reachable.

### Deliberate exception: the viewer uses pdfrx directly

`features/viewer` uses pdfrx's `PdfViewer` widget rather than routing rendering
through `PdfEngine`. `PdfViewer` is a UI component with its own tile cache,
scroll physics and bitmap lifecycle; reimplementing that over `renderPage`
would be worse code and worse performance.

`PdfEngine` remains the only path for **headless** work — text extraction,
outline, permissions — which is what unit tests exercise.

## The write path is a separate interface

`PdfEngine` has no write method, and SP-2a deliberately did not add one. Page
editing goes through `PdfPageEditor`, a separate interface with a single
`materialise` method.

Merging them would have been less code and would have silently dissolved the
guarantee for every existing `PdfEngine` caller. The Definition of Done for
SP-2a includes a check that `PdfEngine` is still write-free.

Editing is **staged**: a `PageEditSession` holds an ordered `List<PageSlot>` and
a command stack, and every operation is a list manipulation in pure Dart. Only
"Apply" materialises. Three consequences follow — undo is a stack of in-memory
snapshots rather than a history of file writes, the operation logic is
unit-testable with no simulator, and an abandoned session cannot leave partial
files behind.

## One write path into the library

Every produced document enters through `DocumentWriter.store`. Metadata
re-attachment lives there, so a new writer cannot forget it — which is exactly
how the SP-2b data-loss bug happened, in a private method only one caller could
reach.

## Annotations are written, not overlaid

Text markup becomes real PDF annotation objects rather than rows in Folio's
database drawn over the page. Database-backed markup would have been far simpler,
and invisible to every other viewer — which defeats what "annotate" means.

The write uses the same incremental-update technique as metadata, with one extra
requirement: the page dictionary must be **overridden** to carry `/Annots`. That
is what `PdfObjectReader` exists for. It matches dictionaries by brace balance
rather than regex, and merges into an existing `/Annots` array rather than
replacing it. It parses page dictionaries and nothing else, deliberately.

`Annotation` is a **sealed** supertype of `TextMarkup` and `DrawingAnnotation`,
so the writer's switch over annotation kinds is exhaustive: adding a kind
without teaching the writer about it is a compile error, not a silently
dropped annotation. Dart only allows a sealed type to be extended inside its
own library, so the three types are one library made of `part` files.

Both kinds share one `AnnotationSession`, and therefore one undo stack and one
Save. Two parallel sessions would have given the user two undo stacks and
produced two documents from a single editing sitting.

## Screen coordinates are converted at one tested boundary

A drawing is captured in canvas pixels and must be written in PDF user space,
which is y-**up** and measured in points. Getting that flip wrong puts every
stroke at the mirror image of where the user drew it.

The conversion is two pure functions, `canvasToPdf` and `pdfToCanvas` in
`page_coordinates.dart`, tested directly rather than only through the UI: they
normalise against the page's on-screen rect, so zoom and scroll need no special
handling — a stroke lands under the finger at any zoom because the rect grows
with it.

The drawing preview converts staged points *back* with `pdfToCanvas` rather
than keeping a second copy in canvas space, so what the user sees on screen and
what gets written cannot drift apart.

## Metadata is preserved by incremental update

The writer discards a source document's `/Info`, so page operations would
otherwise silently destroy every document's title and author.

Rather than parse and rewrite the document, `PdfMetadata` appends a **PDF
incremental update**: the original bytes untouched, then a new `/Info` object, a
new xref section listing only it, and a trailer whose `/Prev` chains to the
previous one. Readers walk that chain backwards, so the new `/Info` supersedes
any older one. Roughly 200 bytes of overhead and no object model required.

This assumes a classic xref table, which is what our own writer emits. It would
need extending for PDF 1.5+ cross-reference streams, and is therefore only
applied to documents Folio itself produced.

Re-attachment happens in one place - `PageOperationsRepositoryImpl._store` -
so every operation inherits it, and it is best-effort: a document that cannot be
patched is still written, because losing a title is better than losing the file.

## Document identity

The single most important decision in the data layer.

A file path is a durable handle on Windows and a lie on mobile:

- **iOS/iPadOS** — a picked URL grants temporary access. Reopening after
  relaunch requires a **security-scoped bookmark** captured at pick time.
- **Android** — the Storage Access Framework returns a `content://` URI scoped
  to one grant. Durable reuse requires `takePersistableUriPermission`, and a
  filesystem path cannot be granted one at all.

So `DocumentRef` stores a platform-appropriate handle, never a bare string:

| Variant | Handle | Durable on |
|---|---|---|
| `ManagedRef` | app-owned content-addressed path | everywhere |
| `ExternalRef` + `BookmarkHandle` | security-scoped bookmark | iOS, macOS |
| `ExternalRef` + `ContentUriHandle` | persisted SAF URI | Android |
| `ExternalRef` + `PathHandle` | absolute path | Windows |

### Import copies in

Opening a document copies it into an app-owned library directory under
Application Support. Consequences:

- Recents and Favorites always reopen, on every platform.
- The app owns the file, so atomic-write discipline applies cleanly.
- Costs storage, and the copy is content-addressed so identical bytes
  deduplicate.

"Open in place" remains available and produces an `ExternalRef`, which is
allowed to go stale; unresolvable entries surface as typed failures rather than
crashes.

## Virtual folders

Managed files are stored content-addressed and flat, so collections are a
nullable `collectionId` column rather than real directories. A move is an
`UPDATE`, not a file operation that could fail halfway, and
`onDelete: setNull` guarantees deleting a collection returns its documents to
the root instead of cascading into deleting them.

## Data safety

`SafeFileWriter` implements the required pipeline:

```
input → temp working file (same directory) → validate → flush → atomic rename
```

The temp file is placed in the destination directory so `rename` is atomic
rather than degrading to a cross-volume copy. A failed or rejected write never
leaves a partial file and never clobbers an existing destination.

## Responsive layout

Layout branches on **width class**, never on `Platform.isX`, so a narrow desktop
window behaves like a phone:

| Width | Layout |
|---|---|
| `< 600dp` | bottom navigation, single pane, panels as bottom sheets |
| `600–1024dp` | navigation rail, docked side panels |
| `> 1024dp` | extended rail, docked side panels |

Platform checks are permitted only for genuine capability differences — file
pickers and permissions.
