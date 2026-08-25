# SP-2a Page Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add merge, split, reorder, delete, extract, rotate, duplicate and insert to Folio, without giving the reader the ability to alter a PDF.

**Architecture:** Page edits are **staged**, not applied. A `PageEditSession` holds an ordered `List<PageSlot>` and a command stack; every operation is a list manipulation in pure Dart. Only "Apply" hands the final slot list to `PdfPageEditor` — a new, separate, one-method write interface. `PdfEngine` is untouched and stays read-only, so SP-1's compile-time guarantee survives.

**Tech Stack:** Flutter 3.41.9 · Dart 3.11.5 · pdfrx 2.4.7 (MIT, PDFium BSD-3) · flutter_riverpod 3.3.2 · drift 2.34.3 · file_selector 1.1.0 — all already present, **no new dependencies**.

**Spec:** `docs/superpowers/specs/2026-08-25-sp2a-page-operations-design.md`

## Global Constraints

Inherited from SP-1 and enforced by existing CI. Every task's requirements implicitly include these.

- **`PdfEngine` must not gain a write, save, or export method.** SP-1's guarantee that the reader cannot alter a PDF is a compile-time property. All writing goes through `PdfPageEditor`. There is a Definition-of-Done check for this.
- **Zero AI. Zero network.** `test/offline_guarantee_test.dart` fails the build on a networking dependency, a network API in `lib/`, the Android `INTERNET` permission, or the macOS `network.client` entitlement.
- **No new dependencies.** SP-2a needs none. Any addition must be permissively licensed (MIT/BSD/Apache-2.0) and recorded in `docs/THIRD_PARTY_LICENSES.md` in the same commit; `dart run scripts/check_licenses.dart` fails on GPL/LGPL/AGPL/SSPL and the commercial PDF SDKs.
- **Originals are never modified.** Every output goes through `SafeFileWriter` and becomes a **new** library entry. Verified by hash in integration tests.
- **No hard-coded user-facing strings.** All UI text via `lib/l10n/app_en.arb`, then `flutter gen-l10n`.
- **Never log document content**, text, passwords, filenames or paths. `AppLogger` takes `fileHash`, not names.
- **Layout branches on width class, never `Platform.isX`.** Use `widthClassFor(MediaQuery.sizeOf(context).width)`.
- **`flutter analyze --fatal-infos` must be clean** and `dart format` must produce no changes. Run the analyzer after every implementation step, not just the tests — an info-level lint fails CI.
- **Minimum touch target 48x48dp; screen-reader labels on every interactive element.**

### Working agreements proven in SP-1

- `*.g.dart` is gitignored; run `dart run build_runner build --delete-conflicting-outputs` after touching drift schema.
- Fixtures are generated, not committed: `dart run scripts/make_fixtures.dart`. Integration tests build their own on-device via `integration_test/fixture_helper.dart`.
- A green suite proves nothing until a mutation makes it red. Where this plan asserts a design property, it says how to mutation-test it.
- Integration tests run on device: `flutter test integration_test -d <device>`. iOS simulator is `DFC5606D-37F0-4176-A73D-B8214C7F820F`; Android emulator is `pixel_api35` (`flutter emulators --launch pixel_api35`).

---

## File Structure

| Path | Responsibility |
|---|---|
| `lib/domain/editing/page_slot.dart` | `PageSlot` value type; rotation arithmetic |
| `lib/domain/editing/page_edit_session.dart` | Ordered slots, the operations, undo/redo |
| `lib/domain/editing/split_plan.dart` | Range parsing and validation (pure) |
| `lib/domain/editing/pdf_page_editor.dart` | The one write method in the app |
| `lib/domain/services/edited_name.dart` | `(edited)` → `(edited 2)` naming |
| `lib/engine/pdfrx_page_editor.dart` | pdfrx implementation of the editor |
| `lib/features/pages/providers.dart` | Session state, apply/merge/split actions |
| `lib/features/pages/widgets/page_grid.dart` | Selectable, reorderable thumbnail grid |
| `lib/features/pages/widgets/page_toolbar.dart` | Rotate/delete/duplicate/extract actions |
| `lib/features/pages/split_sheet.dart` | Split flow and range input |
| `test/fakes/fake_page_editor.dart` | Records calls, returns fixed bytes |

---

# Stage 1 — Pure domain logic

No Flutter, no native code. Everything here runs on any CI runner.

---

### Task 1: PageSlot and rotation arithmetic

**Files:**
- Create: `lib/domain/editing/page_slot.dart`
- Test: `test/domain/editing/page_slot_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `PageSlot({required int sourceDocumentId, required int sourcePageIndex, int quarterTurns = 0})` with `PageSlot rotatedBy(int quarterTurns)`, `bool get isRotated`, value equality and `hashCode`

- [ ] **Step 1: Write the failing test**

`test/domain/editing/page_slot_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/page_slot.dart';

void main() {
  group('PageSlot', () {
    test('defaults to no rotation', () {
      const slot = PageSlot(sourceDocumentId: 1, sourcePageIndex: 0);
      expect(slot.quarterTurns, 0);
      expect(slot.isRotated, isFalse);
    });

    test('rotating accumulates', () {
      const slot = PageSlot(sourceDocumentId: 1, sourcePageIndex: 0);
      expect(slot.rotatedBy(1).quarterTurns, 1);
      expect(slot.rotatedBy(1).rotatedBy(1).quarterTurns, 2);
    });

    // Four quarter turns is identity. Getting the modulo wrong here silently
    // produces pages rotated by 360 degrees plus something.
    test('four quarter turns returns to the original orientation', () {
      const slot = PageSlot(sourceDocumentId: 1, sourcePageIndex: 0);
      final spun = slot.rotatedBy(1).rotatedBy(1).rotatedBy(1).rotatedBy(1);
      expect(spun.quarterTurns, 0);
      expect(spun.isRotated, isFalse);
    });

    test('rotating backwards wraps to 3 rather than going negative', () {
      const slot = PageSlot(sourceDocumentId: 1, sourcePageIndex: 0);
      expect(slot.rotatedBy(-1).quarterTurns, 3);
    });

    test('a large rotation normalises into 0..3', () {
      const slot = PageSlot(sourceDocumentId: 1, sourcePageIndex: 0);
      expect(slot.rotatedBy(9).quarterTurns, 1);
      expect(slot.rotatedBy(-9).quarterTurns, 3);
    });

    test('rotating leaves the source untouched', () {
      const slot = PageSlot(sourceDocumentId: 7, sourcePageIndex: 3);
      final rotated = slot.rotatedBy(2);
      expect(rotated.sourceDocumentId, 7);
      expect(rotated.sourcePageIndex, 3);
    });

    test('slots with identical fields are equal', () {
      const a = PageSlot(sourceDocumentId: 1, sourcePageIndex: 2, quarterTurns: 1);
      const b = PageSlot(sourceDocumentId: 1, sourcePageIndex: 2, quarterTurns: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('slots differing only in rotation are not equal', () {
      const a = PageSlot(sourceDocumentId: 1, sourcePageIndex: 2);
      const b = PageSlot(sourceDocumentId: 1, sourcePageIndex: 2, quarterTurns: 1);
      expect(a, isNot(b));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/editing/page_slot_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement**

`lib/domain/editing/page_slot.dart`:
```dart
/// One page in an edit session: which source document it came from, which page
/// within that document, and how far it has been rotated.
///
/// A slot never holds PDF bytes. Editing is staged as a list of these, and only
/// materialised when the user applies the changes.
class PageSlot {
  const PageSlot({
    required this.sourceDocumentId,
    required this.sourcePageIndex,
    this.quarterTurns = 0,
  });

  final int sourceDocumentId;
  final int sourcePageIndex;

  /// Always normalised to 0..3.
  final int quarterTurns;

  bool get isRotated => quarterTurns != 0;

  /// Returns a slot rotated by [quarterTurns] more, wrapping through 0..3 so
  /// four turns is identity and negative turns wrap rather than go negative.
  PageSlot rotatedBy(int quarterTurns) => PageSlot(
    sourceDocumentId: sourceDocumentId,
    sourcePageIndex: sourcePageIndex,
    // Dart's % returns a non-negative result for a positive divisor, which is
    // what makes rotatedBy(-1) land on 3 rather than -1.
    quarterTurns: (this.quarterTurns + quarterTurns) % 4,
  );

  @override
  bool operator ==(Object other) =>
      other is PageSlot &&
      other.sourceDocumentId == sourceDocumentId &&
      other.sourcePageIndex == sourcePageIndex &&
      other.quarterTurns == quarterTurns;

  @override
  int get hashCode =>
      Object.hash(sourceDocumentId, sourcePageIndex, quarterTurns);

  @override
  String toString() =>
      'PageSlot(doc: $sourceDocumentId, page: $sourcePageIndex, '
      'turns: $quarterTurns)';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/editing/page_slot_test.dart`
Expected: PASS — 8 tests

- [ ] **Step 5: Analyze**

Run: `dart format lib test && flutter analyze --fatal-infos`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/domain/editing/page_slot.dart test/domain/editing/page_slot_test.dart
git commit -m "feat: add PageSlot with normalised rotation arithmetic

Rotation wraps through 0..3 so four quarter turns is identity and negative
turns wrap rather than going negative. A slot never holds PDF bytes."
```

---

### Task 2: PageEditSession — operations and undo/redo

**Files:**
- Create: `lib/domain/editing/page_edit_session.dart`
- Test: `test/domain/editing/page_edit_session_test.dart`

**Interfaces:**
- Consumes: `PageSlot` (Task 1)
- Produces: `PageEditSession.fromDocument(int documentId, int pageCount)`; `List<PageSlot> get slots` (unmodifiable); `bool get isDirty`, `bool get canUndo`, `bool get canRedo`, `bool get isEmpty`; `void move(int from, int to)`, `void removeAt(Iterable<int> indices)`, `void duplicateAt(Iterable<int> indices)`, `void rotate(Iterable<int> indices, {required int quarterTurns})`, `void insertFrom(int documentId, int pageCount, {required int at})`, `List<PageSlot> extract(Iterable<int> indices)`, `void undo()`, `void redo()`

The whole point of this task: these are list manipulations, so they are testable with no simulator and no PDFium. Undo/redo is a stack of whole-list snapshots — the lists are tiny (one small object per page) and snapshotting avoids a class of inverse-operation bugs that command objects invite.

- [ ] **Step 1: Write the failing test**

`test/domain/editing/page_edit_session_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/page_edit_session.dart';
import 'package:folio/domain/editing/page_slot.dart';

/// Renders a session as "doc:page" pairs so assertions read clearly.
List<String> shape(PageEditSession s) =>
    s.slots.map((x) => '${x.sourceDocumentId}:${x.sourcePageIndex}').toList();

void main() {
  group('fromDocument', () {
    test('creates one slot per page in order', () {
      final s = PageEditSession.fromDocument(1, 3);
      expect(shape(s), ['1:0', '1:1', '1:2']);
      expect(s.isDirty, isFalse);
      expect(s.canUndo, isFalse);
    });

    test('slots are unmodifiable from outside', () {
      final s = PageEditSession.fromDocument(1, 2);
      expect(
        () => s.slots.add(const PageSlot(sourceDocumentId: 9, sourcePageIndex: 9)),
        throwsUnsupportedError,
      );
    });
  });

  group('move', () {
    test('moves a page forward', () {
      final s = PageEditSession.fromDocument(1, 4)..move(0, 2);
      expect(shape(s), ['1:1', '1:2', '1:0', '1:3']);
    });

    test('moves a page backward', () {
      final s = PageEditSession.fromDocument(1, 4)..move(3, 0);
      expect(shape(s), ['1:3', '1:0', '1:1', '1:2']);
    });

    test('moving to the end works', () {
      final s = PageEditSession.fromDocument(1, 3)..move(0, 2);
      expect(shape(s), ['1:1', '1:2', '1:0']);
    });

    // A no-op move must not mark the session dirty or push an undo entry,
    // or dragging a page and dropping it back would appear to change it.
    test('moving to the same index is a no-op', () {
      final s = PageEditSession.fromDocument(1, 3)..move(1, 1);
      expect(shape(s), ['1:0', '1:1', '1:2']);
      expect(s.isDirty, isFalse);
      expect(s.canUndo, isFalse);
    });

    test('an out-of-range index throws', () {
      final s = PageEditSession.fromDocument(1, 3);
      expect(() => s.move(0, 9), throwsRangeError);
      expect(() => s.move(-1, 0), throwsRangeError);
    });
  });

  group('removeAt', () {
    // Indices shift as you delete. Deleting 0 then 2 from a naive loop removes
    // the wrong page; this is the single most likely bug in the file.
    test('removes a non-contiguous selection correctly', () {
      final s = PageEditSession.fromDocument(1, 5)..removeAt([0, 2, 4]);
      expect(shape(s), ['1:1', '1:3']);
    });

    test('removes a contiguous selection', () {
      final s = PageEditSession.fromDocument(1, 5)..removeAt([1, 2]);
      expect(shape(s), ['1:0', '1:3', '1:4']);
    });

    test('accepts indices in any order', () {
      final s = PageEditSession.fromDocument(1, 5)..removeAt([4, 0, 2]);
      expect(shape(s), ['1:1', '1:3']);
    });

    test('removing every page leaves the session empty', () {
      final s = PageEditSession.fromDocument(1, 2)..removeAt([0, 1]);
      expect(s.slots, isEmpty);
      expect(s.isEmpty, isTrue);
    });

    test('duplicate indices are tolerated', () {
      final s = PageEditSession.fromDocument(1, 3)..removeAt([1, 1]);
      expect(shape(s), ['1:0', '1:2']);
    });
  });

  group('duplicateAt', () {
    test('inserts a copy directly after each selected page', () {
      final s = PageEditSession.fromDocument(1, 3)..duplicateAt([1]);
      expect(shape(s), ['1:0', '1:1', '1:1', '1:2']);
    });

    test('duplicating several pages keeps each copy beside its original', () {
      final s = PageEditSession.fromDocument(1, 3)..duplicateAt([0, 2]);
      expect(shape(s), ['1:0', '1:0', '1:1', '1:2', '1:2']);
    });

    test('a duplicate carries the rotation of its original', () {
      final s = PageEditSession.fromDocument(1, 2)
        ..rotate([0], quarterTurns: 1)
        ..duplicateAt([0]);
      expect(s.slots[0].quarterTurns, 1);
      expect(s.slots[1].quarterTurns, 1);
    });
  });

  group('rotate', () {
    test('rotates only the selected pages', () {
      final s = PageEditSession.fromDocument(1, 3)..rotate([1], quarterTurns: 1);
      expect(s.slots.map((x) => x.quarterTurns), [0, 1, 0]);
    });

    test('rotating four times returns to the original orientation', () {
      final s = PageEditSession.fromDocument(1, 1);
      for (var i = 0; i < 4; i++) {
        s.rotate([0], quarterTurns: 1);
      }
      expect(s.slots.single.quarterTurns, 0);
    });

    // Rotating a mixed selection must advance each page from its own current
    // rotation, not flatten them to a common value.
    test('a selection with different rotations each advances by one', () {
      final s = PageEditSession.fromDocument(1, 2)
        ..rotate([0], quarterTurns: 1)
        ..rotate([0, 1], quarterTurns: 1);
      expect(s.slots.map((x) => x.quarterTurns), [2, 1]);
    });
  });

  group('insertFrom', () {
    test('inserts another document\'s pages at a position', () {
      final s = PageEditSession.fromDocument(1, 2)..insertFrom(2, 2, at: 1);
      expect(shape(s), ['1:0', '2:0', '2:1', '1:1']);
    });

    test('inserts at the beginning', () {
      final s = PageEditSession.fromDocument(1, 2)..insertFrom(2, 1, at: 0);
      expect(shape(s), ['2:0', '1:0', '1:1']);
    });

    test('inserts at the end', () {
      final s = PageEditSession.fromDocument(1, 2)..insertFrom(2, 1, at: 2);
      expect(shape(s), ['1:0', '1:1', '2:0']);
    });

    test('an out-of-range position throws', () {
      final s = PageEditSession.fromDocument(1, 2);
      expect(() => s.insertFrom(2, 1, at: 5), throwsRangeError);
    });
  });

  group('extract', () {
    // Extraction produces a separate document, so it must leave the session
    // being edited completely alone.
    test('returns the selected slots without changing the session', () {
      final s = PageEditSession.fromDocument(1, 4);
      final taken = s.extract([1, 3]);

      expect(taken.map((x) => x.sourcePageIndex), [1, 3]);
      expect(shape(s), ['1:0', '1:1', '1:2', '1:3']);
      expect(s.isDirty, isFalse);
    });

    test('returns slots in list order regardless of selection order', () {
      final s = PageEditSession.fromDocument(1, 4);
      expect(s.extract([3, 0]).map((x) => x.sourcePageIndex), [0, 3]);
    });

    test('extracting nothing returns an empty list', () {
      expect(PageEditSession.fromDocument(1, 2).extract([]), isEmpty);
    });
  });

  group('undo and redo', () {
    test('undo restores the previous order exactly', () {
      final s = PageEditSession.fromDocument(1, 3)..move(0, 2);
      expect(shape(s), ['1:1', '1:2', '1:0']);

      s.undo();
      expect(shape(s), ['1:0', '1:1', '1:2']);
      expect(s.isDirty, isFalse);
    });

    test('redo reapplies the undone change', () {
      final s = PageEditSession.fromDocument(1, 3)..move(0, 2);
      s.undo();
      s.redo();
      expect(shape(s), ['1:1', '1:2', '1:0']);
    });

    test('undo past the beginning is a safe no-op', () {
      final s = PageEditSession.fromDocument(1, 2);
      expect(s.canUndo, isFalse);
      s.undo();
      expect(shape(s), ['1:0', '1:1']);
    });

    test('redo past the end is a safe no-op', () {
      final s = PageEditSession.fromDocument(1, 2)..move(0, 1);
      s.undo();
      s.redo();
      s.redo();
      expect(shape(s), ['1:1', '1:0']);
    });

    test('a new edit after undo discards the redo branch', () {
      final s = PageEditSession.fromDocument(1, 3)..move(0, 2);
      s.undo();
      s.removeAt([0]);

      expect(s.canRedo, isFalse);
      expect(shape(s), ['1:1', '1:2']);
    });

    test('several operations undo one at a time', () {
      final s = PageEditSession.fromDocument(1, 3)
        ..removeAt([0])
        ..rotate([0], quarterTurns: 1);

      s.undo();
      expect(s.slots.first.quarterTurns, 0);
      expect(shape(s), ['1:1', '1:2']);

      s.undo();
      expect(shape(s), ['1:0', '1:1', '1:2']);
      expect(s.canUndo, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/editing/page_edit_session_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement**

`lib/domain/editing/page_edit_session.dart`:
```dart
import 'package:folio/domain/editing/page_slot.dart';

/// A staged set of page edits.
///
/// Operations manipulate an in-memory list of [PageSlot]; no PDF is touched
/// until the caller materialises the result. That is what makes this logic
/// unit-testable with no simulator, and what lets undo be a stack of snapshots
/// rather than a history of file writes.
class PageEditSession {
  PageEditSession._(this._slots);

  factory PageEditSession.fromDocument(int documentId, int pageCount) {
    return PageEditSession._([
      for (var i = 0; i < pageCount; i++)
        PageSlot(sourceDocumentId: documentId, sourcePageIndex: i),
    ]);
  }

  List<PageSlot> _slots;

  /// Whole-list snapshots. The lists are tiny - one small value object per
  /// page - and snapshotting sidesteps a class of bugs that inverse-operation
  /// command objects invite.
  final List<List<PageSlot>> _undoStack = [];
  final List<List<PageSlot>> _redoStack = [];

  late final List<PageSlot> _original = List.of(_slots);

  List<PageSlot> get slots => List.unmodifiable(_slots);

  bool get isEmpty => _slots.isEmpty;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// True when the current order differs from the session's starting point.
  bool get isDirty {
    if (_slots.length != _original.length) return true;
    for (var i = 0; i < _slots.length; i++) {
      if (_slots[i] != _original[i]) return true;
    }
    return false;
  }

  /// Snapshots the current state, runs [change], and clears the redo branch.
  void _mutate(void Function(List<PageSlot> slots) change) {
    final snapshot = List.of(_slots);
    final working = List.of(_slots);
    change(working);
    _undoStack.add(snapshot);
    _redoStack.clear();
    _slots = working;
  }

  void move(int from, int to) {
    RangeError.checkValidIndex(from, _slots, 'from');
    RangeError.checkValidIndex(to, _slots, 'to');
    // A drag that lands where it started must not dirty the session.
    if (from == to) return;

    _mutate((slots) {
      final slot = slots.removeAt(from);
      slots.insert(to, slot);
    });
  }

  void removeAt(Iterable<int> indices) {
    final targets = indices.toSet();
    if (targets.isEmpty) return;
    for (final i in targets) {
      RangeError.checkValidIndex(i, _slots, 'index');
    }

    _mutate((slots) {
      // Descending order, so removing one index cannot shift the next.
      final ordered = targets.toList()..sort((a, b) => b.compareTo(a));
      for (final i in ordered) {
        slots.removeAt(i);
      }
    });
  }

  void duplicateAt(Iterable<int> indices) {
    final targets = indices.toSet();
    if (targets.isEmpty) return;
    for (final i in targets) {
      RangeError.checkValidIndex(i, _slots, 'index');
    }

    _mutate((slots) {
      // Descending, so each insertion cannot shift a not-yet-processed index.
      final ordered = targets.toList()..sort((a, b) => b.compareTo(a));
      for (final i in ordered) {
        slots.insert(i + 1, slots[i]);
      }
    });
  }

  void rotate(Iterable<int> indices, {required int quarterTurns}) {
    final targets = indices.toSet();
    if (targets.isEmpty) return;
    for (final i in targets) {
      RangeError.checkValidIndex(i, _slots, 'index');
    }

    _mutate((slots) {
      for (final i in targets) {
        // Each page advances from its own current rotation, so a mixed
        // selection stays mixed rather than flattening to one value.
        slots[i] = slots[i].rotatedBy(quarterTurns);
      }
    });
  }

  void insertFrom(int documentId, int pageCount, {required int at}) {
    if (at < 0 || at > _slots.length) {
      throw RangeError.range(at, 0, _slots.length, 'at');
    }

    _mutate((slots) {
      slots.insertAll(at, [
        for (var i = 0; i < pageCount; i++)
          PageSlot(sourceDocumentId: documentId, sourcePageIndex: i),
      ]);
    });
  }

  /// Reads a selection out without changing the session: extraction produces a
  /// separate document and leaves the one being edited alone.
  List<PageSlot> extract(Iterable<int> indices) {
    final targets = indices.toSet();
    for (final i in targets) {
      RangeError.checkValidIndex(i, _slots, 'index');
    }
    // List order, not selection order, so the output matches what is on screen.
    final ordered = targets.toList()..sort();
    return [for (final i in ordered) _slots[i]];
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.of(_slots));
    _slots = _undoStack.removeLast();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.of(_slots));
    _slots = _redoStack.removeLast();
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/editing/page_edit_session_test.dart`
Expected: PASS — 28 tests

- [ ] **Step 5: Mutation-test the index-shift guard**

The descending-order deletion is the load-bearing detail. Prove the test catches its absence: in `removeAt`, change the sort to ascending (`(a, b) => a.compareTo(b)`) and run the suite.

Expected: `removes a non-contiguous selection correctly` FAILS. Revert the change and confirm the suite is green again.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add lib/domain/editing/page_edit_session.dart test/domain/editing/page_edit_session_test.dart
git commit -m "feat: add PageEditSession with staged operations and undo

Operations manipulate an in-memory slot list, so the logic is unit-testable
with no simulator and undo is a stack of snapshots rather than a history of
file writes.

Deletion and duplication process indices in descending order so one edit
cannot shift the next; verified by mutation that ascending order breaks the
non-contiguous selection test. A move that lands where it started is a
no-op, so dragging a page and dropping it back does not dirty the session."
```

---

### Task 3: SplitPlan — range parsing

**Files:**
- Create: `lib/domain/editing/split_plan.dart`
- Test: `test/domain/editing/split_plan_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `SplitPlan.everyPage(int pageCount)`, `SplitPlan.parse(String input, {required int pageCount})`; `List<List<int>> get groups` (zero-based page indices per output document); `int get outputCount`. Throws `FormatException` with a human-readable message on invalid input.

- [ ] **Step 1: Write the failing test**

`test/domain/editing/split_plan_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/split_plan.dart';

void main() {
  group('everyPage', () {
    test('produces one output per page', () {
      final plan = SplitPlan.everyPage(3);
      expect(plan.groups, [
        [0],
        [1],
        [2],
      ]);
      expect(plan.outputCount, 3);
    });

    test('a single-page document yields one output', () {
      expect(SplitPlan.everyPage(1).groups, [
        [0],
      ]);
    });
  });

  group('parse', () {
    // Users type 1-based page numbers; everything downstream is 0-based.
    test('a single range converts to zero-based indices', () {
      expect(SplitPlan.parse('1-3', pageCount: 5).groups, [
        [0, 1, 2],
      ]);
    });

    test('comma-separated ranges become separate outputs', () {
      expect(SplitPlan.parse('1-2,4-5', pageCount: 5).groups, [
        [0, 1],
        [3, 4],
      ]);
    });

    test('a bare page number is a single-page group', () {
      expect(SplitPlan.parse('3', pageCount: 5).groups, [
        [2],
      ]);
    });

    test('mixed ranges and single pages', () {
      expect(SplitPlan.parse('1-2,4,6', pageCount: 6).groups, [
        [0, 1],
        [3],
        [5],
      ]);
    });

    test('whitespace is ignored', () {
      expect(SplitPlan.parse(' 1 - 2 , 4 ', pageCount: 5).groups, [
        [0, 1],
        [3],
      ]);
    });

    test('overlapping ranges are allowed and produce both outputs', () {
      expect(SplitPlan.parse('1-3,2-4', pageCount: 5).groups, [
        [0, 1, 2],
        [1, 2, 3],
      ]);
    });

    test('empty input is rejected', () {
      expect(() => SplitPlan.parse('', pageCount: 5), throwsFormatException);
      expect(() => SplitPlan.parse('   ', pageCount: 5), throwsFormatException);
    });

    test('a page beyond the document is rejected', () {
      expect(() => SplitPlan.parse('1-9', pageCount: 5), throwsFormatException);
      expect(() => SplitPlan.parse('7', pageCount: 5), throwsFormatException);
    });

    test('page zero is rejected because input is one-based', () {
      expect(() => SplitPlan.parse('0-2', pageCount: 5), throwsFormatException);
    });

    test('a descending range is rejected', () {
      expect(() => SplitPlan.parse('4-2', pageCount: 5), throwsFormatException);
    });

    test('non-numeric input is rejected', () {
      expect(() => SplitPlan.parse('one-two', pageCount: 5), throwsFormatException);
      expect(() => SplitPlan.parse('1-', pageCount: 5), throwsFormatException);
    });

    test('the failure message names the problem', () {
      expect(
        () => SplitPlan.parse('1-9', pageCount: 5),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('5'),
          ),
        ),
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/editing/split_plan_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement**

`lib/domain/editing/split_plan.dart`:
```dart
/// How a document is divided into several output documents.
///
/// [groups] holds zero-based page indices; user input is one-based, and the
/// conversion happens here so nothing downstream has to think about it.
class SplitPlan {
  const SplitPlan._(this.groups);

  final List<List<int>> groups;

  int get outputCount => groups.length;

  /// One output document per page.
  factory SplitPlan.everyPage(int pageCount) =>
      SplitPlan._([for (var i = 0; i < pageCount; i++) [i]]);

  /// Parses input such as `1-3,7,10-12`.
  ///
  /// Throws [FormatException] with a message suitable for showing to the user.
  factory SplitPlan.parse(String input, {required int pageCount}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter at least one page or range.');
    }

    final groups = <List<int>>[];
    for (final part in trimmed.split(',')) {
      final piece = part.trim();
      if (piece.isEmpty) {
        throw const FormatException('Enter at least one page or range.');
      }

      final bounds = piece.split('-').map((s) => s.trim()).toList();
      if (bounds.length > 2) {
        throw FormatException('"$piece" is not a valid page range.');
      }

      final first = int.tryParse(bounds.first);
      final last = bounds.length == 1 ? first : int.tryParse(bounds[1]);
      if (first == null || last == null) {
        throw FormatException('"$piece" is not a valid page range.');
      }

      if (first < 1 || last < 1) {
        throw const FormatException('Pages are numbered from 1.');
      }
      if (first > pageCount || last > pageCount) {
        throw FormatException(
          'This document has $pageCount pages, so "$piece" is out of range.',
        );
      }
      if (last < first) {
        throw FormatException('"$piece" runs backwards.');
      }

      groups.add([for (var p = first; p <= last; p++) p - 1]);
    }

    return SplitPlan._(groups);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/editing/split_plan_test.dart`
Expected: PASS — 15 tests

- [ ] **Step 5: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add lib/domain/editing/split_plan.dart test/domain/editing/split_plan_test.dart
git commit -m "feat: add SplitPlan range parsing

Converts one-based user input to zero-based indices in one place. Rejects
empty input, page zero, out-of-range pages, descending ranges and
non-numeric text, with messages written to be shown to the user."
```

---

### Task 4: Edited-document naming

**Files:**
- Create: `lib/domain/services/edited_name.dart`
- Test: `test/domain/services/edited_name_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `String editedName(String original)`, `String extractedName(String original, int pageCount)`, `String splitPartName(String original, int part)`

- [ ] **Step 1: Write the failing test**

`test/domain/services/edited_name_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/services/edited_name.dart';

void main() {
  group('editedName', () {
    test('appends (edited) before the extension', () {
      expect(editedName('Invoice.pdf'), 'Invoice (edited).pdf');
    });

    // Without this, repeated edits produce "(edited) (edited) (edited)".
    test('a second edit numbers rather than repeating the suffix', () {
      expect(editedName('Invoice (edited).pdf'), 'Invoice (edited 2).pdf');
    });

    test('numbering continues past two', () {
      expect(editedName('Invoice (edited 2).pdf'), 'Invoice (edited 3).pdf');
      expect(editedName('Invoice (edited 9).pdf'), 'Invoice (edited 10).pdf');
    });

    test('a name with no extension still works', () {
      expect(editedName('Invoice'), 'Invoice (edited)');
    });

    test('a name containing dots keeps the final extension', () {
      expect(editedName('2026.01.invoice.pdf'), '2026.01.invoice (edited).pdf');
    });

    test('the word edited elsewhere in the name is not treated as a suffix', () {
      expect(editedName('edited notes.pdf'), 'edited notes (edited).pdf');
    });
  });

  group('extractedName', () {
    test('names a single extracted page', () {
      expect(extractedName('Invoice.pdf', 1), 'Invoice (1 page).pdf');
    });

    test('names several extracted pages', () {
      expect(extractedName('Invoice.pdf', 3), 'Invoice (3 pages).pdf');
    });
  });

  group('splitPartName', () {
    test('numbers each part', () {
      expect(splitPartName('Invoice.pdf', 1), 'Invoice (part 1).pdf');
      expect(splitPartName('Invoice.pdf', 12), 'Invoice (part 12).pdf');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/services/edited_name_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement**

`lib/domain/services/edited_name.dart`:
```dart
/// Names for documents produced by page operations.
///
/// Applying edits always creates a new library entry, so these run often and
/// must not accumulate suffixes: "(edited)" becomes "(edited 2)", not
/// "(edited) (edited)".

final RegExp _editedSuffix = RegExp(r'^(.*?)\s*\(edited(?:\s+(\d+))?\)$');

({String stem, String extension}) _split(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return (stem: name, extension: '');
  return (stem: name.substring(0, dot), extension: name.substring(dot));
}

String editedName(String original) {
  final parts = _split(original);
  final match = _editedSuffix.firstMatch(parts.stem);

  if (match == null) {
    return '${parts.stem} (edited)${parts.extension}';
  }

  final base = match.group(1)!;
  final current = int.tryParse(match.group(2) ?? '') ?? 1;
  return '$base (edited ${current + 1})${parts.extension}';
}

String extractedName(String original, int pageCount) {
  final parts = _split(original);
  final unit = pageCount == 1 ? 'page' : 'pages';
  return '${parts.stem} ($pageCount $unit)${parts.extension}';
}

String splitPartName(String original, int part) {
  final parts = _split(original);
  return '${parts.stem} (part $part)${parts.extension}';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/services/edited_name_test.dart`
Expected: PASS — 10 tests

- [ ] **Step 5: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add lib/domain/services/edited_name.dart test/domain/services/edited_name_test.dart
git commit -m "feat: add naming for edited, extracted and split outputs

Repeated edits number the suffix instead of repeating it, so a document
edited three times is '(edited 3)' rather than '(edited) (edited) (edited)'."
```

---

# Stage 2 — The write path

Ends with: PDF bytes actually produced, and round-trips verified on a device.

---

### Task 5: PdfPageEditor interface and test fake

**Files:**
- Create: `lib/domain/editing/pdf_page_editor.dart`
- Create: `test/fakes/fake_page_editor.dart`
- Modify: `lib/core/errors/app_failure.dart`, `lib/core/errors/failure_messages.dart`, `lib/l10n/app_en.arb`
- Test: `test/domain/editing/fake_page_editor_test.dart`

**Interfaces:**
- Consumes: `PageSlot` (Task 1), `PdfDocumentHandle` from `lib/domain/engine/pdf_types.dart`
- Produces: `abstract interface class PdfPageEditor` with `Future<Uint8List> materialise({required List<PageSlot> slots, required Map<int, PdfDocumentHandle> sources})`; `FakePageEditor` recording `List<List<PageSlot>> calls`; new failures `EmptyDocument` and `InvalidPageRange`

**This interface is the only write path in the application.** Do not add a write method to `PdfEngine` — SP-1's guarantee that the reader cannot alter a PDF depends on it having none, and the Definition of Done checks for it.

- [ ] **Step 1: Add the two new failure variants**

In `lib/core/errors/app_failure.dart`, after `StorageFull`:
```dart
final class EmptyDocument extends AppFailure {
  const EmptyDocument({super.technicalDetail});
  @override
  String get code => 'empty_document';
}

final class InvalidPageRange extends AppFailure {
  const InvalidPageRange({super.technicalDetail});
  @override
  String get code => 'invalid_page_range';
}
```

- [ ] **Step 2: Run the analyzer to see the exhaustive switch break**

Run: `flutter analyze`
Expected: **error** `non_exhaustive_switch_expression` in `failure_messages.dart`.

This is the property SP-1 verified by mutation, doing its job: a failure cannot ship without user-facing copy.

- [ ] **Step 3: Add the strings and the mappings**

Add to `lib/l10n/app_en.arb`:
```json
{
  "errorEmptyDocumentTitle": "Nothing to save.",
  "errorEmptyDocumentBody": "This document has no pages left. Add or restore a page before saving.",
  "errorInvalidPageRangeTitle": "That page range isn't valid.",
  "errorInvalidPageRangeBody": "Check the page numbers and try again."
}
```

Run `flutter gen-l10n`, then add to the `switch` in `lib/core/errors/failure_messages.dart`:
```dart
    EmptyDocument() => FailureMessage(
      l10n.errorEmptyDocumentTitle,
      l10n.errorEmptyDocumentBody,
    ),
    InvalidPageRange() => FailureMessage(
      l10n.errorInvalidPageRangeTitle,
      l10n.errorInvalidPageRangeBody,
    ),
```

Run: `flutter analyze --fatal-infos`
Expected: `No issues found!`

- [ ] **Step 4: Write the interface**

`lib/domain/editing/pdf_page_editor.dart`:
```dart
import 'dart:typed_data';

import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// The only write path in the application.
///
/// Deliberately separate from `PdfEngine`, which stays read-only so SP-1's
/// compile-time guarantee that the reader cannot alter a PDF survives. Do not
/// merge these two interfaces.
abstract interface class PdfPageEditor {
  /// Materialises [slots] into PDF bytes.
  ///
  /// [sources] maps a source document id to an already-open handle. Every
  /// slot's `sourceDocumentId` must be present, or [ArgumentError] is thrown.
  ///
  /// Throws `EmptyDocument` when [slots] is empty: a PDF with no pages is not
  /// a valid document, and writing one would produce a file that fails to
  /// reopen.
  Future<Uint8List> materialise({
    required List<PageSlot> slots,
    required Map<int, PdfDocumentHandle> sources,
  });
}
```

- [ ] **Step 5: Write the failing fake test**

`test/domain/editing/fake_page_editor_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/engine/pdf_types.dart';

import '../../fakes/fake_page_editor.dart';

void main() {
  const handle = PdfDocumentHandle(id: 'h1', pageCount: 3);

  test('records the slots it was asked to materialise', () async {
    final editor = FakePageEditor();
    await editor.materialise(
      slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      sources: const {1: handle},
    );

    expect(editor.calls, hasLength(1));
    expect(editor.calls.single.single.sourcePageIndex, 0);
  });

  test('returns non-empty bytes', () async {
    final editor = FakePageEditor();
    final bytes = await editor.materialise(
      slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      sources: const {1: handle},
    );
    expect(bytes, isNotEmpty);
  });

  test('an empty slot list throws EmptyDocument', () async {
    final editor = FakePageEditor();
    await expectLater(
      editor.materialise(slots: const [], sources: const {}),
      throwsA(isA<EmptyDocument>()),
    );
  });

  test('a slot referencing an absent source throws ArgumentError', () async {
    final editor = FakePageEditor();
    await expectLater(
      editor.materialise(
        slots: const [PageSlot(sourceDocumentId: 99, sourcePageIndex: 0)],
        sources: const {1: handle},
      ),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/domain/editing/fake_page_editor_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 7: Implement the fake**

`test/fakes/fake_page_editor.dart`:
```dart
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/editing/pdf_page_editor.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// In-memory [PdfPageEditor] for unit tests.
///
/// Enforces the same preconditions as the real implementation so callers can
/// be tested against them without a device.
class FakePageEditor implements PdfPageEditor {
  final List<List<PageSlot>> calls = [];

  @override
  Future<Uint8List> materialise({
    required List<PageSlot> slots,
    required Map<int, PdfDocumentHandle> sources,
  }) async {
    if (slots.isEmpty) {
      throw const EmptyDocument(technicalDetail: 'fake: no slots');
    }
    for (final slot in slots) {
      if (!sources.containsKey(slot.sourceDocumentId)) {
        throw ArgumentError.value(
          slot.sourceDocumentId,
          'sources',
          'no handle supplied for this source document',
        );
      }
    }

    calls.add(List.of(slots));
    // %PDF header so callers that sniff the magic bytes behave realistically.
    return Uint8List.fromList([0x25, 0x50, 0x44, 0x46, slots.length]);
  }
}
```

- [ ] **Step 8: Run to verify it passes**

Run: `flutter test test/domain/editing/fake_page_editor_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 9: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: add PdfPageEditor write interface and test fake

The only write path in the app, deliberately separate from PdfEngine so
SP-1's compile-time guarantee that the reader cannot alter a PDF survives.

Adds EmptyDocument and InvalidPageRange failures. The exhaustive switch
refused to compile until both had user-facing copy, which is the property
SP-1 verified by mutation working as intended."
```

---

### Task 6: PdfrxPageEditor — the real implementation

**Files:**
- Create: `lib/engine/pdfrx_page_editor.dart`
- Test: `integration_test/page_editor_test.dart`

**Interfaces:**
- Consumes: `PdfPageEditor` (Task 5), `PageSlot` (Task 1), `PdfrxEngine`'s handle map
- Produces: `PdfrxPageEditor implements PdfPageEditor`, constructed with `PdfrxPageEditor(this._engine)` where `_engine` is a `PdfrxEngine`

pdfrx's page-tree write API was proven in SP-1's spike: `createNew` → set `pages` → `assemble` → `encodePdf`, with rotation applied via `page.rotatedTo(...)`. This task wires our slot list to it.

- [ ] **Step 1: Expose the underlying pdfrx document from PdfrxEngine**

`PdfrxPageEditor` needs the real `rx.PdfDocument` behind a `PdfDocumentHandle`. Add to `lib/engine/pdfrx_engine.dart`:
```dart
  /// Internal access for [PdfrxPageEditor]. Not part of [PdfEngine]: exposing
  /// it there would give every reader a route to the write path.
  rx.PdfDocument documentFor(PdfDocumentHandle handle) => _resolve(handle);
```

- [ ] **Step 2: Implement the editor**

`lib/engine/pdfrx_page_editor.dart`:
```dart
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/editing/pdf_page_editor.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

/// [PdfPageEditor] backed by pdfrx / PDFium.
///
/// Builds a fresh document and assigns it pages drawn from the source
/// documents, which is the write path SP-1's spike verified round-trips with
/// order and rotation intact.
class PdfrxPageEditor implements PdfPageEditor {
  PdfrxPageEditor(this._engine);

  final PdfrxEngine _engine;

  static const List<rx.PdfPageRotation> _rotations = [
    rx.PdfPageRotation.none,
    rx.PdfPageRotation.clockwise90,
    rx.PdfPageRotation.clockwise180,
    rx.PdfPageRotation.clockwise270,
  ];

  @override
  Future<Uint8List> materialise({
    required List<PageSlot> slots,
    required Map<int, PdfDocumentHandle> sources,
  }) async {
    if (slots.isEmpty) {
      throw const EmptyDocument(technicalDetail: 'no pages to write');
    }

    for (final slot in slots) {
      if (!sources.containsKey(slot.sourceDocumentId)) {
        throw ArgumentError.value(
          slot.sourceDocumentId,
          'sources',
          'no handle supplied for this source document',
        );
      }
    }

    try {
      final output = await rx.PdfDocument.createNew(sourceName: 'edited.pdf');

      output.pages = [
        for (final slot in slots)
          _pageFor(slot, sources[slot.sourceDocumentId]!),
      ];

      // Required before encoding: it makes the new document independent of the
      // sources, which must stay open until this returns.
      await output.assemble();
      final bytes = await output.encodePdf();
      await output.dispose();
      return bytes;
    } on rx.PdfException catch (e) {
      throw DocumentCorrupt(technicalDetail: e.toString());
    } catch (e) {
      throw UnknownFailure(technicalDetail: e.toString());
    }
  }

  rx.PdfPage _pageFor(PageSlot slot, PdfDocumentHandle handle) {
    final page = _engine.documentFor(handle).pages[slot.sourcePageIndex];
    if (slot.quarterTurns == 0) return page;

    // rotatedTo is absolute, so compose the page's existing rotation with the
    // slot's accumulated turns rather than replacing it.
    final combined = (page.rotation.index + slot.quarterTurns) % 4;
    return page.rotatedTo(_rotations[combined]);
  }
}
```

- [ ] **Step 3: Write the integration test**

`integration_test/page_editor_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:folio/engine/pdfrx_page_editor.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late PdfrxEngine engine;
  late PdfrxPageEditor editor;

  setUp(() {
    engine = PdfrxEngine();
    editor = PdfrxPageEditor(engine);
  });

  group('PdfrxPageEditor round-trips', () {
    // A write that "succeeded" proves nothing until something reads it back.
    test('reorder survives a round trip', () async {
      final doc = await engine.open(
        FileSource(await fixturePath('sample_3page.pdf')),
      );

      final bytes = await editor.materialise(
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 2),
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 0),
        ],
        sources: {1: doc},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'out.pdf'),
      );
      expect(reopened.pageCount, 2);

      final first = await engine.extractText(reopened, 0);
      expect(first!.fullText, contains('Appendix A'));

      await engine.close(reopened);
      await engine.close(doc);
    });

    test('merge combines two documents in order', () async {
      final a = await engine.open(
        FileSource(await fixturePath('sample_3page.pdf')),
      );
      final b = await engine.open(FileSource(await fixturePath('pages_10.pdf')));

      final bytes = await editor.materialise(
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: 2, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: 2, sourcePageIndex: 1),
        ],
        sources: {1: a, 2: b},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'merged.pdf'),
      );
      expect(reopened.pageCount, 3);

      final first = await engine.extractText(reopened, 0);
      expect(first!.fullText, contains('Confidential Invoice'));
      final second = await engine.extractText(reopened, 1);
      expect(second!.fullText, contains('Section 1'));

      await engine.close(reopened);
      await engine.close(a);
      await engine.close(b);
    });

    // Rotation must change the page geometry, not just a metadata flag.
    test('rotation survives and swaps page geometry', () async {
      final doc = await engine.open(
        FileSource(await fixturePath('sample_3page.pdf')),
      );

      final bytes = await editor.materialise(
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 0, quarterTurns: 1),
        ],
        sources: {1: doc},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'rot.pdf'),
      );
      final info = await engine.pageInfo(reopened, 0);

      expect(info.isLandscape, isTrue, reason: 'A4 portrait rotated 90 degrees');
      expect(info.widthPt, closeTo(842, 1));
      expect(info.heightPt, closeTo(595, 1));

      await engine.close(reopened);
      await engine.close(doc);
    });

    test('duplicate produces two pages with the same content', () async {
      final doc = await engine.open(
        FileSource(await fixturePath('sample_3page.pdf')),
      );

      final bytes = await editor.materialise(
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 2),
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 2),
        ],
        sources: {1: doc},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'dup.pdf'),
      );
      expect(reopened.pageCount, 2);

      final first = await engine.extractText(reopened, 0);
      final second = await engine.extractText(reopened, 1);
      expect(first!.fullText, second!.fullText);

      await engine.close(reopened);
      await engine.close(doc);
    });

    test('an empty slot list throws EmptyDocument', () async {
      await expectLater(
        editor.materialise(slots: const [], sources: const {}),
        throwsA(isA<EmptyDocument>()),
      );
    });

    test('a 1000-page document materialises without exhausting memory', () async {
      final doc = await engine.open(
        FileSource(await fixturePath('pages_1000.pdf')),
      );

      final bytes = await editor.materialise(
        slots: [
          for (var i = 0; i < 1000; i++)
            PageSlot(sourceDocumentId: 1, sourcePageIndex: i),
        ],
        sources: {1: doc},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'big.pdf'),
      );
      expect(reopened.pageCount, 1000);

      await engine.close(reopened);
      await engine.close(doc);
    });
  });
}
```

- [ ] **Step 4: Generate fixtures and run on the iOS simulator**

```bash
dart run scripts/make_fixtures.dart
flutter test integration_test/page_editor_test.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: PASS — 6 tests.

If `rotatedTo` or `assemble` differ from the names above, correct them against `~/.pub-cache/hosted/pub.dev/pdfrx_engine-0.4.5/lib/src/pdf_document.dart` and note the change in the commit.

- [ ] **Step 5: Run on the Android emulator**

```bash
flutter emulators --launch pixel_api35
flutter test integration_test/page_editor_test.dart -d emulator-5554
```

Expected: PASS — 6 tests. **Demo on the simulator.**

- [ ] **Step 6: Analyze, commit and push**

```bash
dart format lib integration_test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: implement PdfrxPageEditor over PDFium

Builds a fresh document and assigns pages drawn from the sources, the write
path SP-1's spike proved round-trips with order and rotation intact.

Rotation composes with the page's existing rotation rather than replacing
it, since rotatedTo is absolute. Round-trip tests re-open the output and
assert page order by extracted text and rotation by page geometry, because
a write that succeeded proves nothing until something reads it back."
git push -u origin feature/sp2a-page-operations
```

Confirm all four CI jobs pass, including `build-windows`.

---

### Task 7: PageOperationsRepository — writing outputs to the library

**Files:**
- Create: `lib/domain/repositories/page_operations_repository.dart`
- Create: `lib/data/repositories/page_operations_repository_impl.dart`
- Test: `test/data/repositories/page_operations_repository_test.dart`

**Interfaces:**
- Consumes: `PdfPageEditor` (Task 5), `LibraryRepository` + `LibraryDao` + `SafeFileWriter` (SP-1), `editedName`/`extractedName`/`splitPartName` (Task 4), `PageSlot` (Task 1)
- Produces: `abstract interface class PageOperationsRepository` with `Future<LibraryDocument> apply({required int sourceDocumentId, required List<PageSlot> slots})`, `Future<LibraryDocument> merge({required List<int> documentIds})`, `Future<LibraryDocument> extractPages({required int sourceDocumentId, required List<PageSlot> slots})`, `Future<List<LibraryDocument>> split({required int sourceDocumentId, required List<List<int>> groups})`

- [ ] **Step 1: Write the failing test**

`test/data/repositories/page_operations_repository_test.dart`:
```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/page_operations_repository_impl.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/engine/pdf_types.dart';

import '../../fakes/fake_page_editor.dart';

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late FakePageEditor editor;
  late PageOperationsRepositoryImpl ops;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('page_ops');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
    editor = FakePageEditor();
    ops = PageOperationsRepositoryImpl(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
      editor: editor,
      openSource: (doc) async =>
          PdfDocumentHandle(id: 'h${doc.id}', pageCount: 3),
      closeSource: (_) async {},
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<int> seed(String name) async {
    final f = File('${sandbox.path}/src_$name')
      ..writeAsBytesSync([37, 80, 68, 70, 1, 2, 3]);
    final doc = await library.importFile(f.path, displayName: name);
    return doc.id;
  }

  group('apply', () {
    test('creates a new entry and leaves the original untouched', () async {
      final id = await seed('Invoice.pdf');
      final before = await library.resolveReadablePath(
        (await library.all()).single,
      );
      final beforeBytes = await File(before).readAsBytes();

      final result = await ops.apply(
        sourceDocumentId: id,
        slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      );

      expect(result.displayName, 'Invoice (edited).pdf');
      expect(await library.all(), hasLength(2));
      expect(
        await File(before).readAsBytes(),
        beforeBytes,
        reason: 'the original file must be byte-identical afterwards',
      );
    });

    test('an empty slot list is rejected before anything is written', () async {
      final id = await seed('Invoice.pdf');

      await expectLater(
        ops.apply(sourceDocumentId: id, slots: const []),
        throwsA(isA<Exception>()),
      );
      expect(await library.all(), hasLength(1));
    });

    test('editing an edited document numbers the suffix', () async {
      final id = await seed('Invoice.pdf');
      final once = await ops.apply(
        sourceDocumentId: id,
        slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      );
      final twice = await ops.apply(
        sourceDocumentId: once.id,
        slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      );

      expect(twice.displayName, 'Invoice (edited 2).pdf');
    });
  });

  group('merge', () {
    test('produces one document and leaves both sources in place', () async {
      final a = await seed('A.pdf');
      final b = await seed('B.pdf');

      final merged = await ops.merge(documentIds: [a, b]);

      expect(merged.displayName, contains('A'));
      expect(await library.all(), hasLength(3));
    });

    test('merging fewer than two documents is rejected', () async {
      final a = await seed('A.pdf');
      await expectLater(
        ops.merge(documentIds: [a]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('extractPages', () {
    test('names the output by page count', () async {
      final id = await seed('Invoice.pdf');
      final result = await ops.extractPages(
        sourceDocumentId: id,
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 2),
        ],
      );
      expect(result.displayName, 'Invoice (2 pages).pdf');
    });
  });

  group('split', () {
    test('produces one document per group, numbered', () async {
      final id = await seed('Invoice.pdf');
      final parts = await ops.split(
        sourceDocumentId: id,
        groups: const [
          [0],
          [1, 2],
        ],
      );

      expect(parts, hasLength(2));
      expect(parts.first.displayName, 'Invoice (part 1).pdf');
      expect(parts.last.displayName, 'Invoice (part 2).pdf');
      expect(await library.all(), hasLength(3));
    });

    test('an empty group list is rejected', () async {
      final id = await seed('Invoice.pdf');
      await expectLater(
        ops.split(sourceDocumentId: id, groups: const []),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/repositories/page_operations_repository_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Write the interface**

`lib/domain/repositories/page_operations_repository.dart`:
```dart
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/models/library_document.dart';

/// Page operations that produce new library documents.
///
/// Every method creates new entries. None modifies its source, which is what
/// makes these operations safe to offer without a confirmation dialog.
abstract interface class PageOperationsRepository {
  Future<LibraryDocument> apply({
    required int sourceDocumentId,
    required List<PageSlot> slots,
  });

  Future<LibraryDocument> merge({required List<int> documentIds});

  Future<LibraryDocument> extractPages({
    required int sourceDocumentId,
    required List<PageSlot> slots,
  });

  /// [groups] holds zero-based page indices, one list per output document.
  Future<List<LibraryDocument>> split({
    required int sourceDocumentId,
    required List<List<int>> groups,
  });
}
```

- [ ] **Step 4: Implement**

`lib/data/repositories/page_operations_repository_impl.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/editing/pdf_page_editor.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/page_operations_repository.dart';
import 'package:folio/domain/services/edited_name.dart';
import 'package:path/path.dart' as p;

typedef OpenSource = Future<PdfDocumentHandle> Function(LibraryDocument doc);
typedef CloseSource = Future<void> Function(PdfDocumentHandle handle);

class PageOperationsRepositoryImpl implements PageOperationsRepository {
  PageOperationsRepositoryImpl({
    required LibraryRepository library,
    required SafeFileWriter writer,
    required Directory libraryRoot,
    required PdfPageEditor editor,
    required OpenSource openSource,
    required CloseSource closeSource,
  }) : _library = library,
       _writer = writer,
       _root = libraryRoot,
       _editor = editor,
       _open = openSource,
       _close = closeSource;

  final LibraryRepository _library;
  final SafeFileWriter _writer;
  final Directory _root;
  final PdfPageEditor _editor;
  final OpenSource _open;
  final CloseSource _close;

  Future<LibraryDocument> _documentById(int id) async =>
      (await _library.all()).firstWhere((d) => d.id == id);

  /// Opens the needed sources, materialises, then always closes them, so a
  /// failure part-way cannot leak native handles.
  Future<Uint8List> _materialise(
    List<PageSlot> slots,
    List<LibraryDocument> sources,
  ) async {
    final handles = <int, PdfDocumentHandle>{};
    try {
      for (final doc in sources) {
        handles[doc.id] = await _open(doc);
      }
      return await _editor.materialise(slots: slots, sources: handles);
    } finally {
      for (final handle in handles.values) {
        await _close(handle);
      }
    }
  }

  /// Writes bytes into the library as a new content-addressed document.
  Future<LibraryDocument> _store(Uint8List bytes, String displayName) async {
    final hash = sha256.convert(bytes).toString();
    final relative = p.join(hash.substring(0, 2), '$hash.pdf');

    await _writer.write(
      destination: File(p.join(_root.path, relative)),
      produce: (working) => working.writeAsBytes(bytes, flush: true),
      validate: (working) async => await working.length() == bytes.length,
    );

    return _library.registerManaged(
      relativePath: relative,
      contentHash: hash,
      displayName: displayName,
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<LibraryDocument> apply({
    required int sourceDocumentId,
    required List<PageSlot> slots,
  }) async {
    final source = await _documentById(sourceDocumentId);
    final bytes = await _materialise(slots, [source]);
    return _store(bytes, editedName(source.displayName));
  }

  @override
  Future<LibraryDocument> merge({required List<int> documentIds}) async {
    if (documentIds.length < 2) {
      throw ArgumentError.value(
        documentIds,
        'documentIds',
        'merging needs at least two documents',
      );
    }

    final sources = <LibraryDocument>[];
    for (final id in documentIds) {
      sources.add(await _documentById(id));
    }

    final handles = <int, PdfDocumentHandle>{};
    final slots = <PageSlot>[];
    try {
      for (final doc in sources) {
        final handle = await _open(doc);
        handles[doc.id] = handle;
        for (var i = 0; i < handle.pageCount; i++) {
          slots.add(PageSlot(sourceDocumentId: doc.id, sourcePageIndex: i));
        }
      }
      final bytes = await _editor.materialise(slots: slots, sources: handles);
      return await _store(bytes, editedName(sources.first.displayName));
    } finally {
      for (final handle in handles.values) {
        await _close(handle);
      }
    }
  }

  @override
  Future<LibraryDocument> extractPages({
    required int sourceDocumentId,
    required List<PageSlot> slots,
  }) async {
    final source = await _documentById(sourceDocumentId);
    final bytes = await _materialise(slots, [source]);
    return _store(bytes, extractedName(source.displayName, slots.length));
  }

  @override
  Future<List<LibraryDocument>> split({
    required int sourceDocumentId,
    required List<List<int>> groups,
  }) async {
    if (groups.isEmpty) {
      throw ArgumentError.value(groups, 'groups', 'split needs at least one group');
    }

    final source = await _documentById(sourceDocumentId);
    final created = <LibraryDocument>[];

    try {
      for (var part = 0; part < groups.length; part++) {
        final slots = [
          for (final index in groups[part])
            PageSlot(sourceDocumentId: source.id, sourcePageIndex: index),
        ];
        final bytes = await _materialise(slots, [source]);
        created.add(
          await _store(bytes, splitPartName(source.displayName, part + 1)),
        );
      }
      return created;
    } catch (_) {
      // A partial split would litter the library with a half-finished set, so
      // remove what was already written before rethrowing.
      for (final doc in created) {
        await _library.delete(doc.id);
      }
      rethrow;
    }
  }
}
```

- [ ] **Step 5: Add `registerManaged` to LibraryRepository**

The implementation above needs a way to register already-written bytes. Add to `lib/domain/repositories/library_repository.dart`:
```dart
  /// Registers a file already written into the library root. Used by page
  /// operations, which produce bytes rather than importing an external file.
  Future<LibraryDocument> registerManaged({
    required String relativePath,
    required String contentHash,
    required String displayName,
    required int sizeBytes,
  });
```

And to `lib/data/repositories/library_repository_impl.dart`:
```dart
  @override
  Future<LibraryDocument> registerManaged({
    required String relativePath,
    required String contentHash,
    required String displayName,
    required int sizeBytes,
  }) async {
    final id = await _dao.insertDocument(
      ref: ManagedRef(relativePath: relativePath, contentHash: contentHash),
      displayName: displayName,
      sizeBytes: sizeBytes,
    );
    return (await all()).firstWhere((d) => d.id == id);
  }
```

Add the same method to the `_FakeRepo` in `test/features/home/library_controller_test.dart` so it still satisfies the interface:
```dart
  @override
  Future<LibraryDocument> registerManaged({
    required String relativePath,
    required String contentHash,
    required String displayName,
    required int sizeBytes,
  }) async {
    final doc = _make(displayName);
    docs.add(doc);
    return doc;
  }
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/data/repositories/page_operations_repository_test.dart`
Expected: PASS — 9 tests

- [ ] **Step 7: Run the whole suite, analyze, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add PageOperationsRepository

Every operation writes a new library entry through SafeFileWriter and
leaves its source byte-identical, asserted directly by test. A split that
fails part-way removes the outputs it already wrote rather than leaving a
half-finished set in the library. Source handles are closed in a finally
block so a failure cannot leak native handles."
```

---

# Stage 3 — User interface

Ends with: all eight operations reachable and demonstrated on the simulator.

---

### Task 8: Pages mode — grid, selection, reorder

**Files:**
- Create: `lib/features/pages/providers.dart`, `lib/features/pages/widgets/page_grid.dart`, `lib/features/pages/widgets/page_toolbar.dart`
- Modify: `lib/features/viewer/viewer_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/pages/page_session_controller_test.dart`

**Interfaces:**
- Consumes: `PageEditSession` (Task 2), `PageOperationsRepository` (Task 7)
- Produces: `pageOperationsRepositoryProvider`, `pageSessionProvider` (an `AutoDisposeNotifierProvider<PageSessionController, PageSessionState>`), `PageSessionState({required PageEditSession session, required Set<int> selection, required bool busy})`

- [ ] **Step 1: Add the strings**

Add to `lib/l10n/app_en.arb`:
```json
{
  "pagesMode": "Pages",
  "readMode": "Read",
  "pagesSelectedCount": "{count} selected",
  "@pagesSelectedCount": { "placeholders": { "count": { "type": "int" } } },
  "pagesSelectAll": "Select all",
  "pagesClearSelection": "Clear selection",
  "pagesRotateLeft": "Rotate left",
  "pagesRotateRight": "Rotate right",
  "pagesDelete": "Delete pages",
  "pagesDuplicate": "Duplicate pages",
  "pagesExtract": "Extract to new document",
  "pagesInsert": "Insert pages from…",
  "pagesUndo": "Undo",
  "pagesRedo": "Redo",
  "pagesApply": "Save as new document",
  "pagesDiscard": "Discard changes",
  "pagesDiscardPrompt": "Discard your page changes? The original document is untouched either way.",
  "pagesApplied": "Saved as {name}",
  "@pagesApplied": { "placeholders": { "name": { "type": "String" } } },
  "pagesSplit": "Split document",
  "pagesMerge": "Merge documents",
  "pagesEmptyWarning": "A document must have at least one page."
}
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing controller test**

`test/features/pages/page_session_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/pages/providers.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    container.read(pageSessionProvider.notifier).start(documentId: 1, pageCount: 4);
  });

  tearDown(() => container.dispose());

  PageSessionController get controller =>
      container.read(pageSessionProvider.notifier);
  PageSessionState get state => container.read(pageSessionProvider);

  group('selection', () {
    test('starts empty', () {
      expect(state.selection, isEmpty);
    });

    test('toggling adds then removes', () {
      controller.toggleSelection(2);
      expect(state.selection, {2});
      controller.toggleSelection(2);
      expect(state.selection, isEmpty);
    });

    test('select all selects every page', () {
      controller.selectAll();
      expect(state.selection, {0, 1, 2, 3});
    });

    // Stale indices after a delete would act on the wrong pages next time.
    test('deleting clears the selection', () {
      controller.toggleSelection(1);
      controller.deleteSelected();
      expect(state.selection, isEmpty);
      expect(state.session.slots, hasLength(3));
    });
  });

  group('operations', () {
    test('rotate applies to the selection only', () {
      controller.toggleSelection(0);
      controller.rotateSelected(1);
      expect(state.session.slots[0].quarterTurns, 1);
      expect(state.session.slots[1].quarterTurns, 0);
    });

    test('operations with no selection do nothing', () {
      controller.rotateSelected(1);
      expect(state.session.isDirty, isFalse);
    });

    test('deleting every page is refused', () {
      controller.selectAll();
      controller.deleteSelected();
      expect(
        state.session.slots,
        isNotEmpty,
        reason: 'a document must keep at least one page',
      );
    });

    test('undo is reflected in state', () {
      controller.toggleSelection(0);
      controller.deleteSelected();
      expect(state.session.slots, hasLength(3));

      controller.undo();
      expect(state.session.slots, hasLength(4));
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/pages/page_session_controller_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 4: Implement the controller**

`lib/features/pages/providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/editing/page_edit_session.dart';
import 'package:folio/domain/repositories/page_operations_repository.dart';

/// Overridden at app start with the real implementation, and in tests with a
/// fake. Reading it unoverridden is a programming error, not a runtime state.
final pageOperationsRepositoryProvider = Provider<PageOperationsRepository>(
  (ref) => throw UnimplementedError(
    'pageOperationsRepositoryProvider must be overridden',
  ),
);

class PageSessionState {
  const PageSessionState({
    required this.session,
    required this.selection,
    required this.busy,
  });

  final PageEditSession session;
  final Set<int> selection;
  final bool busy;

  PageSessionState copyWith({
    PageEditSession? session,
    Set<int>? selection,
    bool? busy,
  }) => PageSessionState(
    session: session ?? this.session,
    selection: selection ?? this.selection,
    busy: busy ?? this.busy,
  );
}

final pageSessionProvider =
    NotifierProvider<PageSessionController, PageSessionState>(
      PageSessionController.new,
    );

class PageSessionController extends Notifier<PageSessionState> {
  @override
  PageSessionState build() => PageSessionState(
    session: PageEditSession.fromDocument(0, 0),
    selection: const {},
    busy: false,
  );

  void start({required int documentId, required int pageCount}) {
    state = PageSessionState(
      session: PageEditSession.fromDocument(documentId, pageCount),
      selection: const {},
      busy: false,
    );
  }

  /// The session mutates in place, so emit a new state object to notify
  /// listeners without pretending the session itself is immutable.
  void _touch({Set<int>? selection}) {
    state = state.copyWith(selection: selection ?? state.selection);
  }

  void toggleSelection(int index) {
    final next = Set<int>.of(state.selection);
    next.contains(index) ? next.remove(index) : next.add(index);
    _touch(selection: next);
  }

  void selectAll() => _touch(
    selection: {for (var i = 0; i < state.session.slots.length; i++) i},
  );

  void clearSelection() => _touch(selection: const {});

  void move(int from, int to) {
    state.session.move(from, to);
    // Indices shift on reorder, so a stale selection would highlight the
    // wrong pages.
    _touch(selection: const {});
  }

  void deleteSelected() {
    if (state.selection.isEmpty) return;
    // Refuse rather than produce a zero-page document, which is not a valid
    // PDF and would fail to reopen.
    if (state.selection.length >= state.session.slots.length) return;

    state.session.removeAt(state.selection);
    _touch(selection: const {});
  }

  void duplicateSelected() {
    if (state.selection.isEmpty) return;
    state.session.duplicateAt(state.selection);
    _touch(selection: const {});
  }

  void rotateSelected(int quarterTurns) {
    if (state.selection.isEmpty) return;
    state.session.rotate(state.selection, quarterTurns: quarterTurns);
    _touch();
  }

  void insertFrom(int documentId, int pageCount, {required int at}) {
    state.session.insertFrom(documentId, pageCount, at: at);
    _touch(selection: const {});
  }

  void undo() {
    state.session.undo();
    _touch(selection: const {});
  }

  void redo() {
    state.session.redo();
    _touch(selection: const {});
  }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/pages/page_session_controller_test.dart`
Expected: PASS — 8 tests

- [ ] **Step 6: Build the grid**

`lib/features/pages/widgets/page_grid.dart` renders `ReorderableGridView`-style behaviour using Flutter's `ReorderableListView` in a wrap layout, or a `GridView` with `LongPressDraggable`/`DragTarget` if grid reordering proves awkward. Each cell shows `PdfPageView(document: doc, pageNumber: slot.sourcePageIndex + 1)` inside a `RotatedBox(quarterTurns: slot.quarterTurns)`, with a selection checkmark overlay and a `Semantics(label: l10n.viewerPageLabel(index + 1), selected: isSelected, button: true)` wrapper.

Tapping toggles selection; dragging calls `controller.move`. Use `itemExtent`-bounded lazy building so a 1000-page document does not render every thumbnail.

- [ ] **Step 7: Build the toolbar**

`lib/features/pages/widgets/page_toolbar.dart` shows the selected count and buttons for rotate left/right, delete, duplicate, extract and insert — each disabled when the selection is empty — plus undo/redo bound to `session.canUndo`/`canRedo`, and a filled **Save as new document** action enabled only when `session.isDirty`.

- [ ] **Step 8: Add the mode toggle to the viewer**

In `lib/features/viewer/viewer_screen.dart`, add a `_ViewerMode { read, pages }` field. In `read` mode the body is the existing `PdfViewer`; in `pages` mode it is `PageGrid` above `PageToolbar`. Switching into pages mode calls `start(documentId:, pageCount: _totalPages)`. Leaving with `session.isDirty` prompts with `l10n.pagesDiscardPrompt`.

- [ ] **Step 9: Verify on the simulator**

```bash
flutter run -d DFC5606D-37F0-4176-A73D-B8214C7F820F --dart-define-from-file=config/development.json
```

Open a document, switch to Pages, select pages, rotate, delete, drag to reorder, undo, redo, then Save as new document. Confirm a new entry appears and the original opens unchanged. **Demo this on the simulator.**

- [ ] **Step 10: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add Pages mode with selection, reorder and undo

Reordering and deleting clear the selection, because indices shift
underneath and a stale selection would act on the wrong pages. Deleting
every page is refused rather than producing a zero-page document, which is
not a valid PDF and would fail to reopen."
```

---

### Task 9: Merge, split and insert flows

**Files:**
- Create: `lib/features/pages/split_sheet.dart`
- Modify: `lib/features/home/library_screen.dart`, `lib/features/home/widgets/document_tile.dart`, `lib/features/pages/widgets/page_toolbar.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/pages/split_sheet_test.dart`

**Interfaces:**
- Consumes: `SplitPlan` (Task 3), `PageOperationsRepository` (Task 7), `pageSessionProvider` (Task 8)
- Produces: `SplitSheet` widget; library multi-select mode

- [ ] **Step 1: Add the strings**

```json
{
  "splitEveryPage": "Every page becomes its own document",
  "splitByRanges": "Custom ranges",
  "splitRangeHint": "e.g. 1-3, 7, 10-12",
  "splitOutputCount": "{count} documents will be created",
  "@splitOutputCount": { "placeholders": { "count": { "type": "int" } } },
  "librarySelectMode": "Select documents",
  "libraryMergeSelected": "Merge selected",
  "mergeNeedsTwo": "Select at least two documents to merge."
}
```

- [ ] **Step 2: Write the failing split-sheet test**

`test/features/pages/split_sheet_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/split_plan.dart';

void main() {
  // The sheet's live preview is exactly this computation, so testing it here
  // covers the behaviour without pumping a widget.
  group('split preview', () {
    test('every page yields one output per page', () {
      expect(SplitPlan.everyPage(7).outputCount, 7);
    });

    test('valid ranges yield one output per range', () {
      expect(SplitPlan.parse('1-3,5', pageCount: 8).outputCount, 2);
    });

    test('invalid input surfaces a message rather than a count', () {
      expect(
        () => SplitPlan.parse('1-99', pageCount: 8),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

- [ ] **Step 3: Run to verify it passes**

Run: `flutter test test/features/pages/split_sheet_test.dart`
Expected: PASS — 3 tests (SplitPlan already exists from Task 3)

- [ ] **Step 4: Build the split sheet**

`lib/features/pages/split_sheet.dart` offers two modes: every page, or custom ranges with a text field. As the user types, parse with `SplitPlan.parse` and show either `l10n.splitOutputCount(plan.outputCount)` or the `FormatException` message beneath the field. The confirm button is disabled while the input is invalid. Confirming calls `PageOperationsRepository.split`.

- [ ] **Step 5: Add library multi-select and merge**

In `lib/features/home/library_screen.dart`, add a selection mode toggled from the app bar. In selection mode each `DocumentTile` shows a checkbox and tapping toggles rather than opens. A **Merge selected** action is enabled at two or more and calls `PageOperationsRepository.merge`, then exits selection mode and shows the new document.

- [ ] **Step 6: Wire insert-from in the toolbar**

`Insert pages from…` opens a document chooser listing other library documents. Choosing one calls `controller.insertFrom(id, pageCount, at: selection.isEmpty ? slots.length : selection.first)`.

- [ ] **Step 7: Verify each flow on the simulator**

Merge two documents and confirm the page count is the sum. Split by `1-2,3` and confirm two new documents. Insert one document into another and confirm the pages land at the chosen position. **Demo this on the simulator.**

- [ ] **Step 8: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add merge, split and insert flows

Split previews its output count live and refuses to run while the range is
invalid, so the error is visible before anything is written. Merge requires
two documents and is reached from library multi-select, because merging
inherently spans files."
```

---

# Stage 4 — End-to-end verification and documentation

---

### Task 10: End-to-end flows, both platforms, and docs

**Files:**
- Create: `integration_test/page_operations_flow_test.dart`
- Modify: `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/TESTING.md`, `docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: everything above
- Produces: verified feature status

- [ ] **Step 1: Write the end-to-end flows**

`integration_test/page_operations_flow_test.dart` drives real widgets and asserts on visible text:

1. Open a document, enter Pages mode, confirm one cell per page.
2. Select a page, delete it, confirm the grid shrinks by one.
3. Undo, confirm it returns.
4. Rotate a page, apply, reopen the output, assert the page is landscape.
5. Reorder by drag, apply, reopen, assert order by extracted text.
6. Extract two pages, confirm a `(2 pages)` document appears.
7. Split into two parts, confirm two `(part N)` documents appear.
8. Merge two documents from the library, confirm the combined page count.
9. **After every one of the above, assert the source file's SHA-256 is unchanged.**
10. Attempt to delete every page, confirm it is refused and the document still has pages.

- [ ] **Step 2: Run on the iOS simulator**

```bash
dart run scripts/make_fixtures.dart
flutter test integration_test -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including SP-1's existing suites.

- [ ] **Step 3: Run on the Android emulator**

```bash
flutter emulators --launch pixel_api35
flutter test integration_test -d emulator-5554
```

Expected: all pass. Until this passes, no Android claim may be made.

- [ ] **Step 4: Verify PdfEngine is still write-free**

```bash
grep -nE "(write|save|export|encode)" lib/domain/engine/pdf_engine.dart
```

Expected: no method declarations matching. This is the SP-1 guarantee SP-2a promised not to break.

- [ ] **Step 5: Update the documentation**

- `docs/FEATURES.md` — add the eight operations, ✅ where verified on that platform and 🟡 for Windows, which stays built-but-unexercised.
- `docs/ARCHITECTURE.md` — document the `PdfEngine` / `PdfPageEditor` split and why it exists.
- `docs/LIMITATIONS.md` — remove "SP-1 does not modify PDFs at all" and replace it with what is still absent: annotations, metadata, encryption authoring, redaction, compression. Add any page-count ceiling found in Step 2.
- `docs/TESTING.md` — refresh the counts and the last-measured date.

- [ ] **Step 6: Full verification**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
```

Business-logic coverage must remain at or above 80%; `lib/domain/editing/` should be at or above 90%, since it is pure Dart with no excuse for gaps.

- [ ] **Step 7: Commit, push and confirm CI**

```bash
git add -A
git commit -m "test: add end-to-end page operation flows and update docs

Every flow asserts the source document's hash is unchanged afterwards,
which is the property that makes these operations safe to offer without a
confirmation dialog. Verified on the iOS simulator and Android emulator."
git push origin feature/sp2a-page-operations
```

Confirm all four CI jobs pass, including `build-windows`.

---

## Definition of done

- [ ] All eight operations implemented and reachable from the UI
- [ ] `PdfEngine` still has no write method (Task 10, Step 4)
- [ ] `lib/domain/editing/` unit coverage ≥90%; overall business logic ≥80%
- [ ] Integration round-trips pass on iOS simulator **and** Android emulator
- [ ] `flutter analyze --fatal-infos` clean; format clean; licence audit passes
- [ ] CI green on all four jobs including `build-windows`
- [ ] Source documents verified byte-identical by hash after every operation
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `TESTING.md`, `ARCHITECTURE.md` updated

Report the phase status in the brief's format:

```
PHASE STATUS
------------
Implemented:
Tests:
Platforms Verified:
Known Issues:
Dependencies Added:
License:
Next Phase:
```

**Next:** SP-2b — the object layer — opening with a throwaway spike on whether qpdf builds through Dart native assets on all four platforms. Its scope is decided by that answer, not before it.
