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
      const a = PageSlot(
        sourceDocumentId: 1,
        sourcePageIndex: 2,
        quarterTurns: 1,
      );
      const b = PageSlot(
        sourceDocumentId: 1,
        sourcePageIndex: 2,
        quarterTurns: 1,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('slots differing only in rotation are not equal', () {
      const a = PageSlot(sourceDocumentId: 1, sourcePageIndex: 2);
      const b = PageSlot(
        sourceDocumentId: 1,
        sourcePageIndex: 2,
        quarterTurns: 1,
      );
      expect(a, isNot(b));
    });
  });
}
