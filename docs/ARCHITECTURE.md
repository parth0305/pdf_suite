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
