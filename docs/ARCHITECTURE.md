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

## One object index, two narrow readers

`PdfObjectIndex` maps an object number to its latest dictionary. It owns the
two mechanics any object lookup needs: dictionaries matched by brace balance,
and **the last definition of an object number wins**, which is what a reader
walking the trailer chain backwards sees.

That second rule is not a detail. Reading a superseded page dictionary merges
into a stale `/Annots` and orphans every annotation saved before it — a
data-loss bug that shipped in SP-3a and was found only when a spike compared
rendered pixels rather than bytes.

`PdfObjectReader` still handles page dictionaries and nothing else;
`PdfAnnotationReader` resolves `/Annots` references through the same index.
Two bounded readers, rather than one file growing toward a PDF parser.

## Ink carries strokes, not points

`/InkList` is defined as an array of stroke arrays. SP-3b only ever emitted one,
so a drawing was a single polyline — a shape that cannot represent a signature
without drawing lines through the gaps between pen strokes.

Geometry is therefore `strokes: List<List<PdfPoint>>`, with `points` kept as
`strokes.first` so the fourteen non-ink uses are untouched.

This corrected a live defect: the reader flattened `/InkList`, so restyling a
multi-stroke ink annotation from another tool regenerated its appearance with
the strokes joined. `boundsPt` had the same blind spot and would have bounded
only the first stroke, clipping the rest away via the `/BBox`.

## Appearance streams are per-kind, not universal

Probed on device rather than assumed: a `/Text` note renders **without** an
appearance stream (692 pixels changed), and a `/Stamp` renders **nothing**
without one (0 pixels). So appearance generation is optional per annotation
kind, not a step every annotation goes through.

A note therefore carries no `/AP` at all. Generating one could only disagree
with the icon every viewer already draws, and it would put the note's meaning
in two places at once.

## Standard-14 fonts are referenced, never embedded

Stamp labels are drawn with `/BaseFont /Helvetica` and no font file. The
fourteen standard fonts are built into every conforming viewer, so no font data
is shipped and no font licence is involved — verified on device at 3927 pixels
changed.

The stamp box is **sized from its label** rather than measured:
`2 × padding + label.length × fontSize × 0.75`. 0.75 em is a safe upper bound
for uppercase Helvetica, so the text fits by construction. Carrying a width
table for a font we do not embed is not worth the accuracy.

## Signatures are stored normalised, y-up

A saved signature holds its strokes in a unit box with y increasing upward, the
same orientation as PDF user space, so placement is a multiply and an offset
with no flip. The canvas-to-PDF flip happens once, at capture.

Placement fits the signature inside the dragged box rather than filling it.

## Encryption: two handlers, one reachable

Folio implements both PDF standard security handlers it needs:

| Handler | Cipher | Reachable |
|---|---|---|
| Revision 2 | RC4-40 | **No.** It is the reference the pipeline was proven against, and it is not protection worth offering. |
| Revision 6 | AES-256 | Yes — "Protect with password". |

They differ in a way that is easy to get wrong by analogy: revision 2 derives a
**per-object key** from the file key and the object number, while revision 6
uses the file key **directly** for every string and stream. Applying R2's
scheme under V5 produces a document nothing can open — mutation-tested at
7,308 pixels.

A protected document carries no re-attached metadata. `PdfMetadata` appends an
incremental update, and an unencrypted update sitting after an encrypted
document would defeat the encryption.

## Two write models, and when each applies

Folio writes documents two ways.

**Incremental update** — append new objects, an overridden page dictionary, a
new cross-reference section and a trailer chaining to the previous one. The
original bytes are never touched. Everything through SP-4a works this way:
metadata, annotations, watermarks.

**Full rewrite** — parse every object, emit them all, write a fresh
cross-reference table and a trailer with no `/Prev`. Verified by rendering: a
rewritten document differs from its original by **zero pixels**.

Encryption is what forces the second. Encrypting a document means encrypting
every string and every stream in it, so every object must be re-emitted; there
is nothing to append. Compressing an existing document and redacting one need
the same thing.

Two rules the rewrite depends on:

- **`/Length` decides where an object ends**, not the word `endobj`. Binary
  stream data can contain those bytes, and searching for them ends the object
  inside its own stream.
- **`/Encrypt` and the document `/ID` are never encrypted.** A reader needs
  both in the clear before it can derive any key.

Each object is encrypted with its **own** key, derived from the file key and
the object number. Reusing the file key produces a document that opens in some
readers and not others — mutation-tested at 7,308 pixels.

## Writing page content, and what it costs

SP-4a is the first slice that writes page **content** rather than annotations.
It appends a content stream to each page's `/Contents` and overrides the page
dictionary — proved on device at 3,075 pixels changed with the original bytes
byte-identical.

Three rules make it safe:

- **The stream is `q`/`Q` balanced.** It runs after the page's own content, and
  an unbalanced stream leaks graphics state into everything appended after it.
- **`/Resources` is merged, never replaced.** Replacing strips the fonts the
  page's own content depends on and the page renders blank. Asserting both
  entries are merely *present* is not enough — a writer that appends a second
  `/Resources` passes that check while a reader takes only one of them, so the
  test asserts there is exactly one.
- **`/MediaBox` is resolved through inheritance**, in a sibling file rather
  than in `PdfObjectReader`: following `/Parent` means reading a node that is
  not a page dictionary, which that reader's own documentation forbids.

## Why compression and encryption are not here

Both were probed alongside watermarks. Neither can be done by appending: an
incremental update only ever *grows* a file, so compressing by appending is
self-defeating, and encrypting a document means every string and stream in it
must be encrypted. Both need a full-file rewrite, which is a separate decision.

`dart:io`'s `ZLibCodec` is available with no dependency and PDFium accepts a
stream we compressed, so Flate itself is not the obstacle — the write model is.

## Moving is a rect rewrite, and the appearance follows

Probed on device: changing only `/Rect` moved a mark from columns 20..59 to
200..239, and enlarging `/Rect` scaled it from 40 to 120 columns. PDFium
implements the ISO 32000-1 §12.5.5 mapping of an appearance `/BBox` onto its
`/Rect`, so **no appearance is regenerated when an annotation moves**.

The geometry keys are rewritten by the same affine anyway, so `/Rect` and
`/InkList`, `/L` and `/QuadPoints` never disagree. That is *not* because a
stale geometry would render wrongly — it would not, since the BBox mapping
rescues it — but because the file would be internally inconsistent for viewers
that do not honour `/AP` and for any code that reads geometry positionally.

The consequence for testing is sharp: **this class of bug is invisible to
rendering**. It can only be caught by reading the geometry back.

Because the transform works on the raw dictionary, it needs no reconstruction —
which is why a stamp can be moved even though Folio cannot rebuild one well
enough to restyle it.

## An edit may never move what it did not compute

Restyling copies every geometry key out of the source dictionary as a raw
substring. Only `/C`, `/BS` and `/AP` are rewritten. Moving is the one
operation that *is* a request to change geometry, and is the stated exception.

`pdfNumber` formats to two decimals, so re-emitting geometry from parsed
doubles would shift an annotation by up to 0.005pt — invisible in review,
invisible in every byte assertion, and permanent. A mutation test enforces it.

The appearance stream is regenerated from parsed values, which is fine: an
appearance is derived, and the error is orders of magnitude below visibility.

## In-place editing repoints a row; it does not overwrite a file

Managed files are content-addressed, so editing a document's bytes changes
where it lives. Rewriting in place means writing the new file, repointing the
library row, and deleting the old file **only when no other row references
it** — identical documents are stored once, so deleting on one document's
behalf would break every other document sharing it.

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
