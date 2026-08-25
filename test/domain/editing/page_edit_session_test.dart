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
        () => s.slots.add(
          const PageSlot(sourceDocumentId: 9, sourcePageIndex: 9),
        ),
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
      final s = PageEditSession.fromDocument(1, 3)
        ..rotate([1], quarterTurns: 1);
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
    test("inserts another document's pages at a position", () {
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
