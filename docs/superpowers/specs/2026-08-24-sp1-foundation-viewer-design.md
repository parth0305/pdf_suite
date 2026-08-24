# SP-1 — Foundation + Viewer (Design)

- **Date:** 2026-08-24
- **Status:** Approved for planning
- **Covers:** Phases 0–4 of the project brief
- **Delivers:** a read-only, offline PDF reader on iOS, iPadOS, Android and Windows

---

## 1. Program context

The full brief spans 24 phases and roughly 34 features. That is too large for one
spec, so it is decomposed into ten sub-projects, each with its own
design → plan → implement → verify cycle.

| # | Sub-project | Brief phases | Depends on |
|---|---|---|---|
| **SP-1** | **Foundation + Viewer** | **0–4** | — |
| SP-2 | PDF object layer + page operations | 5 | SP-1 |
| SP-3 | Annotations + signatures | 6, 8 | SP-2 |
| SP-4 | Content creation (text, image, watermark, metadata) | 7, 14, 15 | SP-2 |
| SP-5 | Security + redaction | 12, 13 | SP-2 |
| SP-6 | Scanner + OCR | 9, 10 | SP-1 |
| SP-7 | Compression | 11 | SP-2, SP-4 |
| SP-8 | Batch + automation | 16, 17 | most |
| SP-9 | Printing + sharing | 18, 19 | SP-1 |
| SP-10 | Hardening + release | 20–24 | all |

This document specifies **SP-1 only**.

---

## 2. Evidence: the pdfrx spike

A throwaway spike ran on the iPhone 16 Plus simulator (iOS 18.6) on 2026-08-24.
Six probes, six passes. The results below are measured, not predicted, and they
determine the engine boundary in §4.

| Probe | Result |
|---|---|
| Open + parse a 3-page PDF | PASS — 3 pages, 595x842pt |
| Raster render a page | PASS — 300x424 px bitmap |
| Text extraction with per-character rects | PASS — 87 chars, 87 rects |
| Search and locate a token across pages | PASS — found page 3 at (202, 709) |
| Reorder + rotate + duplicate + encode | PASS — 3867 bytes written |
| Round-trip: reopen and verify | PASS — 4 pages, order held, rotation held, geometry swapped 595x842 → 842x595 |

Timings: pod install 5.3s, Xcode build 46.4s, document load 9ms, 4-page viewer load 4ms.

### What pdfrx provides

Rendering, per-character text geometry, search, document outline, password-protected
open, permission introspection, and — unexpectedly — **page-tree write operations**
via `PdfDocument.createNew()`, a settable `pages` list, `assemble()` and `encodePdf()`.
Page rotation via `page.rotatedTo()`. Image-to-PDF via `createFromJpegData()`.

This means the whole of brief Phase 5 (merge, split, reorder, delete, extract,
rotate, duplicate, insert) is an SP-2 UI problem rather than an engine problem.

### What pdfrx does not provide

Verified absent by reading `pdfrx_engine` 0.4.5 source:

- **No document metadata API.** No `/Info` dictionary access of any kind.
- **`PdfAnnotation` is read-only** and surfaces only title/content/subject/dates
  derived from links. No annotation authoring.
- **No encryption authoring.** `encodePdf(removeSecurity: true)` can strip
  security; nothing can apply it.
- **No content-stream object access**, so true redaction cannot be built on it.
- **No compression controls.**

These five gaps define the scope of the Dart object layer built in SP-2 and used
by SP-4, SP-5 and SP-7. They are out of scope for SP-1.

### Known engine risk

pdfrx uses Dart's native-assets / build-hooks mechanism (`hook/`, `code_assets`,
`hooks`, `objective_c`) rather than a classic Flutter plugin; its pubspec declares
no `plugin.platforms`. The iOS build emits a non-fatal
`Target native_assets required define SdkRoot but it was not provided`. It built
and ran correctly, but this is the most likely source of cross-platform friction,
particularly on the Windows CI runner. Treat any Windows build failure here as
suspect number one.

---

## 3. Goals and non-goals

### Goals

1. A user can open a PDF from device storage and read it comfortably on all four platforms.
2. Large documents (1,000+ pages) never block the UI thread.
3. Search, text selection, and copy work on text-bearing PDFs.
4. The app functions with networking fully disabled.
5. Business logic reaches ≥80% unit coverage **without** requiring a simulator.
6. Every dependency is permissively licensed and recorded.

### Non-goals for SP-1

Any operation that alters the *contents* of a PDF. SP-1 ships a reader: it never
parses, rewrites, or re-encodes PDF content, so no document can be corrupted by it.

It does perform whole-file operations as library management — copy on import,
rename, duplicate, move, delete — and these go through `SafeFileWriter` (§6). The
distinction is exact and load-bearing: SP-1 moves files around, it never opens a
PDF's byte stream for modification. `PdfEngine` (§4) exposes no write method at
all, which enforces this at the type level rather than by convention.

Also excluded: OCR, scanning, annotation, printing, sharing, cloud of any kind, AI
of any kind.

---

## 4. Architecture

```
Flutter UI  (features/*)
      │
Application / Domain  (domain/*)      ← pure Dart, no Flutter, no native
      │
Repository interfaces (domain/repositories)
      │
Data layer  (data/*)                  ← drift, file system, platform channels
      │
PdfEngine interface (domain/engine)   ← the swap point required by brief §5
      │
      ├─ PdfrxEngine     → pdfrx → PDFium   (production)
      └─ FakePdfEngine                      (unit tests, no native code)
```

### Directory layout

```
pdf_suite/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── constants/        breakpoints, durations, limits
│   │   ├── errors/           AppFailure hierarchy + user-message mapping
│   │   ├── logging/          AppLogger (see §10)
│   │   ├── permissions/      runtime permission wrappers
│   │   ├── storage/          SafeFileWriter, app directories
│   │   ├── theme/            light/dark themes, typography, spacing
│   │   └── utilities/        formatters, extensions
│   ├── domain/
│   │   ├── engine/           PdfEngine, PdfDocumentHandle, PdfPageInfo
│   │   ├── models/           DocumentRef, LibraryDocument, ViewerState…
│   │   ├── repositories/     LibraryRepository, DocumentRepository (interfaces)
│   │   └── services/         search, sorting, recents policy
│   ├── data/
│   │   ├── local/            drift database, DAOs
│   │   ├── file_system/      pickers, resolver, app library directory
│   │   └── repositories/     concrete implementations
│   ├── engine/               PdfrxEngine implementation
│   ├── features/
│   │   ├── home/             library, recents, favorites, search, sort
│   │   ├── viewer/           reader, thumbnails, search UI, outline
│   │   └── settings/         theme, defaults, about, licenses
│   ├── l10n/                 arb files
│   └── widgets/              AdaptiveScaffold, shared components
├── test/                     unit — must run with no simulator
├── integration_test/         end-to-end — requires device/simulator
├── test_documents/           generated fixtures (see §12)
├── docs/
└── scripts/                  fixture generation, license audit
```

### Why `PdfEngine` is an interface

PDFium is native code. Tests that touch it require a simulator or device, which
the Ubuntu and Windows CI runners do not have. Routing all domain logic through an
interface lets unit tests inject `FakePdfEngine` and run everywhere. Without this,
the ≥80% coverage target in brief §29 is unreachable on CI. The interface is a
testability requirement first and a swappability requirement second.

```dart
abstract interface class PdfEngine {
  Future<PdfDocumentHandle> open(
    DocumentBytesSource source, {
    PasswordCallback? onPasswordRequired,
  });

  Future<PdfPageInfo> pageInfo(PdfDocumentHandle doc, int pageIndex);

  Future<RenderedPage> renderPage(
    PdfDocumentHandle doc,
    int pageIndex, {
    required int targetWidth,
    required int targetHeight,
  });

  Future<PageText?> extractText(PdfDocumentHandle doc, int pageIndex);

  Future<List<OutlineNode>> outline(PdfDocumentHandle doc);

  Future<DocumentPermissions?> permissions(PdfDocumentHandle doc);

  Future<void> close(PdfDocumentHandle doc);
}
```

`PageText` carries `fullText` plus per-character rectangles — the spike confirmed
PDFium supplies these, and SP-5 redaction and SP-6 OCR both depend on them later.

---

## 5. Document identity and access

The single most important design decision in SP-1.

A file path is a durable handle on Windows and a lie on mobile:

- **iOS/iPadOS** — `UIDocumentPicker` grants temporary access. Reopening after
  relaunch requires a **security-scoped bookmark** captured at pick time.
  A persisted path fails silently on next launch.
- **Android** — the Storage Access Framework returns a `content://` URI scoped to
  one grant. Durable reuse requires `takePersistableUriPermission`. Under scoped
  storage, raw paths are largely unusable.

### `DocumentRef`

```dart
sealed class DocumentRef {
  const DocumentRef();
}

/// File copied into the app-owned library. Always reopenable.
final class ManagedRef extends DocumentRef {
  final String relativePath;   // relative to library root
  final String contentHash;    // integrity + duplicate detection
}

/// External file opened in place. May become unresolvable.
final class ExternalRef extends DocumentRef {
  final ExternalHandle handle; // bookmark blob | persisted URI | absolute path
  final String displayName;
}
```

`DocumentResolver` turns a `DocumentRef` into readable bytes and returns a typed
failure (`DocumentMoved`, `PermissionRevoked`, `DocumentCorrupt`) rather than
throwing a raw platform exception. Recents entries that fail to resolve are shown
greyed with a "Locate again" action — never silently dropped, never a crash.

### Default: import copies in

Opening a document copies it into an app-owned library directory. Consequences:

- Recents and Favorites always reopen, on every platform.
- The app owns the file, so brief §37's atomic-write discipline applies cleanly
  from SP-2 onward.
- Costs storage, and users may ask where "their" file went — mitigated by showing
  the original filename and an explicit "Imported copy" badge.

"Open in place" remains available for one-off viewing and is clearly labelled as
not added to the library. Its refs are `ExternalRef` and are allowed to go stale.

---

## 6. Data safety

`SafeFileWriter` implements brief §37 and is built in SP-1 even though SP-1 never
writes a PDF, so it is proven before anything depends on it:

```
input → temp working file in same volume → validate → fsync → atomic rename → output
```

Rules, enforced by tests:

- Originals are never modified. Operations produce new outputs.
- A partially written file is never visible under the destination name.
- Temp files are cleaned up on both success and failure paths.
- Same-volume temp placement, so `rename` is atomic rather than a copy.

---

## 7. Design system

Original visual design. No Acrobat imitation in layout, iconography, or naming.

- Material 3, seeded colour scheme, full **light and dark** themes.
- Typography scale honouring OS text-size settings (brief §35).
- Minimum touch target 48x48dp.
- Visible focus indicators for keyboard navigation.
- All strings via ARB from the first commit (brief §36). English only in SP-1;
  no hard-coded user-facing text anywhere.

### Responsive shells

| Breakpoint | Layout | Primary target |
|---|---|---|
| `< 600dp` | Bottom navigation, single pane | iPhone |
| `600–1024dp` | Navigation rail, two-pane split | iPad |
| `> 1024dp` | Sidebar, multi-pane, menu bar | Windows |

A single `AdaptiveScaffold` owns this. **Feature code never branches on
`Platform.isX` for layout** — only on width class. Platform checks are permitted
solely for genuine capability differences (file pickers, permissions).

---

## 8. Features

### F1 — File management (brief Phase 3)

| Capability | Acceptance criterion |
|---|---|
| Open / import PDF | Native picker on each platform; non-PDF rejected with a clear message |
| Save As / duplicate / rename / delete / move | Operate on library entries; originals preserved |
| Recent documents | Ordered by last opened; survives relaunch; unresolvable entries greyed, not dropped |
| Favorites | Toggle; persists |
| Search files | Matches filename and title; case-insensitive; incremental |
| Sort | Name, date added, date opened, size — ascending and descending |
| Folder navigation | Within the app library |

### F2 — PDF viewer (brief Phase 4)

| Capability | Acceptance criterion |
|---|---|
| Page rendering | Asynchronous; UI thread never blocked |
| Zoom | Pinch, double-tap, and explicit controls; keyboard zoom on desktop |
| Page navigation | Scroll, jump-to-page, next/previous |
| Thumbnails | Lazy-rendered side panel; tap to jump |
| Full-screen | Chrome hides; restores on tap |
| Dark mode | App chrome themed; page rendering inversion offered as an explicit option |
| Search | Cross-document; hit list; hits highlighted using char rects |
| Text selection + copy | Selection rendered from char rects; copies to clipboard |
| Bookmarks / outline | Document outline shown when present |
| Rotation | View-only rotation; **does not modify the file** (that is SP-2) |
| Password-protected PDFs | Prompt on open; wrong password re-prompts; cancel returns cleanly |

### Performance requirements (brief §11)

- Page bitmaps are cached with an LRU bound; off-screen bitmaps are disposed.
- The whole document is never resident in memory at once.
- Rendering happens off the UI isolate.
- Verified against the fixture matrix in §12.

---

## 9. Error handling

Typed `AppFailure` hierarchy. Raw exceptions and stack traces never reach the UI
(brief §34). Each failure maps to a localized message:

> **Unable to open this PDF.**
> The file may be corrupted or use an unsupported PDF feature.

Technical detail — exception type, file size, page index, engine message — goes to
the log only. PDFs are treated as untrusted input: malformed files must fail safely
with a message, never crash the app. Any PDF-embedded JavaScript is never executed;
PDFium's JS engine stays disabled.

---

## 10. Logging

Local only. Never leaves the device. Per brief §38, each record carries operation,
start time, end time, file size, result, and error code.

**Never logged:** PDF content, extracted text, passwords, file contents, or
document titles. File identity is logged as a hash, never a name or path.

---

## 11. Dependencies

Every entry license-verified before adoption; recorded in
`docs/THIRD_PARTY_LICENSES.md`, which SP-1 creates.

| Package | License | Purpose |
|---|---|---|
| `pdfrx` ^2.4.7 | MIT | Viewer, render, text, search |
| ↳ bundled PDFium | BSD-3-Clause | PDF engine |
| `flutter_riverpod` | MIT | State management |
| `drift` + `sqlite3_flutter_libs` | MIT / public domain | Library database |
| `file_selector` | BSD-3-Clause | Native file pickers |
| `path_provider` | BSD-3-Clause | App directories |
| `intl`, `flutter_localizations` | BSD-3-Clause | Localization |
| `logging` | BSD-3-Clause | Logging |

No GPL, LGPL, or AGPL. No commercial SDK. No network-dependent service.

**`syncfusion_flutter_pdf` is explicitly rejected.** Its LICENSE requires either a
Syncfusion Community License (gross revenue under USD 1M and fewer than five
developers) or a paid commercial license, and states the product may not be used
without one. That conflicts with brief §4 and with distributing this app freely.
Recorded here so the decision is not silently revisited.

---

## 12. Testing

### Unit tests — no simulator required

Repositories, `DocumentRef` resolution and failure modes, `SafeFileWriter` atomicity
and cleanup, search, sorting, recents policy, error-to-message mapping, theme
selection. All against `FakePdfEngine`. Target ≥80% coverage of `domain/` and `data/`.

### Integration tests — simulator or device

Open → render → search → select → copy. Password-protected open. Recents surviving
relaunch. Corrupt-file handling.

### Fixture matrix

`scripts/make_fixtures.dart` generates into `test_documents/`:

| Fixture | Purpose |
|---|---|
| 1, 10, 100, 500, 1000, 5000 pages | Open time, render, navigation, memory |
| Image-heavy | Memory pressure |
| Large scanned (no text layer) | Confirms search finds nothing rather than failing |
| Password-protected | Auth flow |
| Corrupt / truncated | Safe failure |
| Malformed xref | Safe failure |
| Embedded JavaScript | Must not execute |

Fixtures are generated, not committed, keeping the repository small and the inputs
reproducible.

---

## 13. CI

GitHub Actions, free runners only (brief §40).

**Pull request:** `flutter analyze`, `flutter test`, `dart format --set-exit-if-changed`,
license audit script.

**Main:** the above plus `flutter build apk`, `flutter build ios --no-codesign`,
and `flutter build windows` on `windows-latest`.

The Windows runner is the **only** verification Windows receives. It proves the code
compiles and unit tests pass; it proves nothing about the Windows user experience.

---

## 14. Definition of done

Per brief §43, SP-1 is complete only when all of the following hold:

- [ ] UI implemented for F1 and F2
- [ ] Business logic complete behind repository interfaces
- [ ] Typed error handling with localized user messages
- [ ] Persistence working and surviving relaunch
- [ ] Unit tests ≥80% on `domain/` and `data/`
- [ ] Integration tests passing on iOS simulator
- [ ] `flutter analyze` clean, zero errors
- [ ] Fixture matrix opens without crash, including 1000-page and corrupt files
- [ ] Offline verified with networking disabled
- [ ] Android verified on an AVD (which must first be created)
- [ ] Windows builds green on CI
- [ ] `DEVELOPMENT_SETUP.md`, `ARCHITECTURE.md`, `THIRD_PARTY_LICENSES.md`, `LIMITATIONS.md` written

A feature is not done because its UI exists.

---

## 15. Known limitations at SP-1 exit

To be recorded in `docs/LIMITATIONS.md`:

1. **Windows has no manual QA.** CI proves compilation and unit tests only. Mouse,
   touch, File Explorer drag/drop and printing are unverified.
2. **No write operations at all.** By design; SP-2 onward.
3. **Search finds nothing in scanned PDFs** with no text layer. Expected — OCR is SP-6.
4. **View rotation is not persisted** to the file. SP-2.
5. **English only.** Architecture supports more; no translations yet.
6. **pdfrx native-assets mechanism is new** and is the likeliest cross-platform
   failure point, especially on Windows.

---

## 16. Next

On approval of this document, the writing-plans skill converts it into a phased
implementation plan with review checkpoints. Each phase ends with a build, a test
run, and a demonstration on the iOS simulator before the next begins.
