# SP-2a — Page Operations (Design)

- **Date:** 2026-08-25
- **Status:** Approved for planning
- **Covers:** Phase 5 of the project brief
- **Depends on:** SP-1 (merged to `develop` as 642bd127)

---

## 1. Why this sub-project changed shape

The original decomposition bundled "Dart PDF object layer + page operations"
into one sub-project, on the assumption that page operations required an object
layer.

SP-1 disproved that. The feasibility spike showed pdfrx/PDFium already provides
page-tree writes:

```dart
final out = await PdfDocument.createNew(sourceName: 'out.pdf');
out.pages = [...pages from any documents, reordered, rotated...];
await out.assemble();
final bytes = await out.encodePdf();
```

That round-trip was verified: four pages, order preserved, and rotation
preserved with page geometry correctly swapping 595x842 to 842x595.

So the bundle split. **SP-2a is page operations only** and needs no new engine
work. The object layer becomes SP-2b, whose shape waits on a separate spike.

### The qpdf question, reopened

qpdf (Apache-2.0) was rejected during initial design because cross-compiling C++
for Android NDK, iOS, and MSVC looked like heavy build engineering.

SP-1 produced evidence against that specific fear: PDFium and SQLite both build
through Dart native assets, and `build-windows` passed on first attempt. A
follow-up check confirmed `native_toolchain_c` exposes `Language.cpp` and
`cppLinkStdLib`, so C++ is supported.

**This lowers the risk; it does not eliminate it.** qpdf is roughly 200 source
files with a generated config header and a zlib dependency, so the open question
is qpdf's *build system*, not the language. SP-2b begins with a throwaway spike
that answers it. SP-2a does not depend on the outcome either way.

---

## 2. Scope

All eight Phase 5 operations:

| Operation | Result |
|---|---|
| Merge | multiple documents into one |
| Split | one document into many |
| Reorder | pages rearranged |
| Delete | pages removed |
| Extract | selected pages as a new document |
| Rotate | per page, per selection, or whole document |
| Duplicate | selected pages repeated |
| Insert | pages from another document |

### Out of scope

Metadata, annotation authoring, encryption authoring, content-stream access and
compression. Those are SP-2b through SP-7.

---

## 3. The structural decision: PdfEngine stays write-free

SP-1 ships a guarantee that the reader **cannot** alter a PDF, enforced by
`PdfEngine` having no write method — a compile error, not a convention.

Adding a write method to `PdfEngine` would silently dissolve that guarantee for
every existing caller. So page editing gets a **separate interface**:

```dart
/// The only write path in the application. Deliberately separate from
/// PdfEngine, which remains read-only so SP-1's guarantee survives.
abstract interface class PdfPageEditor {
  /// Materialises an ordered slot list into PDF bytes.
  ///
  /// [sources] maps a source document id to an open handle. Every slot's
  /// sourceDocumentId must be present, or ArgumentError is thrown.
  Future<Uint8List> materialise({
    required List<PageSlot> slots,
    required Map<int, PdfDocumentHandle> sources,
  });
}
```

One method. Everything else in SP-2a is pure Dart.

---

## 4. Editing model: staged, not immediate

The heart of the design. Operations never touch a PDF.

```dart
class PageSlot {
  const PageSlot({
    required this.sourceDocumentId,
    required this.sourcePageIndex,
    this.quarterTurns = 0,
  });

  final int sourceDocumentId;
  final int sourcePageIndex;

  /// 0..3. Rotation accumulates modulo 4, so rotating four times is identity.
  final int quarterTurns;
}
```

A `PageEditSession` holds `List<PageSlot>` plus a command stack. Reorder,
delete, duplicate, rotate and insert are list manipulations on that list.
Extract is the exception: it *reads* a selection out without changing the
session, because extraction produces a separate document and leaves the one
being edited alone. Only **Apply** calls `PdfPageEditor.materialise`.

Three consequences, each of which is a reason for this shape:

1. **Undo/redo is a command stack over an in-memory list**, not over files.
2. **The business logic is unit-testable without a simulator** — exactly what
   `FakePdfEngine` achieved for SP-1's repositories. Reordering correctness is
   verified on CI runners, not only on devices.
3. **Nothing is written until the user commits**, so an abandoned session cannot
   leave partial files behind.

### Session API

```dart
class PageEditSession {
  factory PageEditSession.fromDocument(int documentId, int pageCount);

  List<PageSlot> get slots;          // unmodifiable
  bool get isDirty;
  bool get canUndo;
  bool get canRedo;

  void move(int from, int to);
  void removeAt(Iterable<int> indices);
  void duplicateAt(Iterable<int> indices);
  void rotate(Iterable<int> indices, {required int quarterTurns});
  void insertFrom(int documentId, int pageCount, {required int at});
  List<PageSlot> extract(Iterable<int> indices);

  void undo();
  void redo();
}
```

`extract` returns a slot list rather than mutating, because extraction produces
a *new* document and leaves the session unchanged.

---

## 5. Components

| File | Responsibility |
|---|---|
| `lib/domain/editing/page_slot.dart` | the value type |
| `lib/domain/editing/page_edit_session.dart` | slots, operations, undo/redo |
| `lib/domain/editing/pdf_page_editor.dart` | the one-method write interface |
| `lib/domain/editing/split_plan.dart` | range parsing and validation (pure) |
| `lib/engine/pdfrx_page_editor.dart` | pdfrx implementation |
| `lib/features/pages/pages_mode.dart` | grid, selection, drag-reorder |
| `lib/features/pages/widgets/page_grid.dart` | reuses SP-1 thumbnail rendering |
| `lib/features/pages/providers.dart` | session state |
| `test/fakes/fake_page_editor.dart` | records calls; returns fixed bytes |

### Entry points

- **Pages mode** — a toggle in the viewer turning the page area into a
  selectable grid. Reuses SP-1's thumbnail rendering rather than duplicating it.
- **Merge** — from the library, on a multi-selection of two or more documents,
  because merging inherently spans files.
- **Split** — its own flow, because it produces *many* outputs rather than one
  and needs range input rather than grid selection.

---

## 6. Data safety

Unchanged from SP-1's discipline, and it applies to every output here.

- Every write goes through `SafeFileWriter`: temp file in the destination
  directory, validate, flush, atomic rename.
- **Originals are never modified.** Applying edits creates a **new library
  entry**; the source document is untouched.
- Naming avoids the `(edited) (edited)` trap: a document already ending in
  `(edited)` becomes `(edited 2)`, then `(edited 3)`.
- Split writes N outputs. If any one fails, already-written outputs are removed
  so a partial split does not litter the library.

---

## 7. Error handling

Reuses SP-1's `AppFailure` hierarchy. Two new variants:

| Failure | Raised when |
|---|---|
| `EmptyDocument` | applying a session whose slot list is empty |
| `InvalidPageRange` | a split range is malformed or out of bounds |

Both map to localized messages through the existing exhaustive `switch`, which
means adding them without copy is a compile error — the property verified by
mutation in SP-1.

---

## 8. Testing

### Unit — no simulator

`PageEditSession` gets exhaustive coverage, including the cases most likely to
be wrong:

- moving a page to the position it already occupies
- moving to the end of the list
- deleting the final remaining page
- deleting a non-contiguous selection, with indices shifting underneath
- rotating four times returning to the original orientation
- rotating a selection that already carries different rotations
- undo restoring order exactly, and redo reapplying it
- undo past the beginning, and redo past the end
- insert at position 0 and at the end

`SplitPlan` range parsing gets its own tests: `1-3,7,10-12`, overlapping ranges,
descending ranges, out-of-bounds pages, empty input.

### Integration — device

Round-trip verification mirroring the SP-1 spike, because a passing write means
nothing until the output is re-opened:

- merge two documents, reopen, assert combined page count and page order
- reorder, reopen, assert order by extracted text
- rotate, reopen, assert `quarterTurns` **and** that page geometry swapped
- delete, reopen, assert count and that the right pages survived
- extract, reopen, assert only selected pages are present
- split, assert N files exist with the expected page counts
- apply to a 1000-page document without exhausting memory

---

## 9. Definition of done

- [ ] All eight operations implemented and reachable from the UI
- [ ] `PdfEngine` still has no write method
- [ ] Session logic ≥90% unit coverage
- [ ] Integration round-trips pass on iOS simulator and Android emulator
- [ ] `flutter analyze --fatal-infos` clean; format clean; licence audit passes
- [ ] CI green on all four jobs including `build-windows`
- [ ] Originals verified unmodified after every operation, by hash
- [ ] `FEATURES.md` and `LIMITATIONS.md` updated to match what was verified

---

## 10. Next

SP-2b — the object layer — begins with a throwaway spike answering whether qpdf
builds through Dart native assets on all four platforms. Its scope is decided by
that answer, not before it.
