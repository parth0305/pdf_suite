import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';

void main() {
  group('PdfPageInfo', () {
    test('A4 portrait is not landscape', () {
      const info = PdfPageInfo(
        index: 0,
        widthPt: 595,
        heightPt: 842,
        rotationQuarterTurns: 0,
      );
      expect(info.isLandscape, isFalse);
    });

    test('a rotated A4 reports landscape', () {
      const info = PdfPageInfo(
        index: 0,
        widthPt: 842,
        heightPt: 595,
        rotationQuarterTurns: 1,
      );
      expect(info.isLandscape, isTrue);
    });
  });

  group('TextRect', () {
    // PDF user space is y-up: top is numerically GREATER than bottom. Getting
    // this backwards silently inverts every selection highlight.
    test('height is computed from a y-up coordinate system', () {
      const rect = TextRect(left: 60, top: 712, right: 120, bottom: 700);
      expect(rect.height, 12, reason: 'top - bottom, not bottom - top');
      expect(rect.width, 60);
    });

    test('a y-down assumption would produce a negative height', () {
      const rect = TextRect(left: 0, top: 100, right: 10, bottom: 90);
      expect(rect.height.isNegative, isFalse);
    });
  });

  group('PageText', () {
    test('empty text reports isEmpty', () {
      const text = PageText(fullText: '', charRects: []);
      expect(text.isEmpty, isTrue);
    });

    test('non-empty text does not report isEmpty', () {
      const text = PageText(
        fullText: 'a',
        charRects: [TextRect(left: 0, top: 10, right: 5, bottom: 0)],
      );
      expect(text.isEmpty, isFalse);
    });
  });
}
