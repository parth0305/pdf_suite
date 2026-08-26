import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/engine/pdf_types.dart';

const rect = TextRect(left: 60, top: 712, right: 120, bottom: 700);

void main() {
  group('pdfSubtype', () {
    test('maps each kind to its PDF subtype name', () {
      expect(
        const TextMarkup(
          kind: MarkupKind.highlight,
          pageIndex: 0,
          quads: [rect],
        ).pdfSubtype,
        'Highlight',
      );
      expect(
        const TextMarkup(
          kind: MarkupKind.underline,
          pageIndex: 0,
          quads: [rect],
        ).pdfSubtype,
        'Underline',
      );
      // The PDF name is StrikeOut, not Strikethrough - a wrong name here
      // produces an annotation no viewer recognises.
      expect(
        const TextMarkup(
          kind: MarkupKind.strikeOut,
          pageIndex: 0,
          quads: [rect],
        ).pdfSubtype,
        'StrikeOut',
      );
    });
  });

  group('quadPoints', () {
    // ISO 32000-1 Table 179: upper-left, upper-right, lower-left, lower-right.
    // Clockwise ordering is the common mistake and renders wrong.
    test('emits eight numbers per quad in spec order', () {
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect],
      );
      expect(markup.quadPoints, [60, 712, 120, 712, 60, 700, 120, 700]);
    });

    test('concatenates multiple quads', () {
      const second = TextRect(left: 60, top: 690, right: 200, bottom: 678);
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect, second],
      );
      expect(markup.quadPoints, hasLength(16));
      expect(markup.quadPoints.sublist(8), [
        60,
        690,
        200,
        690,
        60,
        678,
        200,
        678,
      ]);
    });

    test('preserves y-up: the first y is the larger value', () {
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect],
      );
      expect(markup.quadPoints[1], greaterThan(markup.quadPoints[5]));
    });
  });

  group('boundingRect', () {
    test('spans every quad', () {
      const a = TextRect(left: 60, top: 712, right: 120, bottom: 700);
      const b = TextRect(left: 40, top: 690, right: 200, bottom: 678);
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [a, b],
      );

      expect(markup.boundingRect.left, 40);
      expect(markup.boundingRect.right, 200);
      expect(markup.boundingRect.top, 712);
      expect(markup.boundingRect.bottom, 678);
    });
  });

  group('pdfColour', () {
    test('converts ARGB to PDF components in 0..1', () {
      const yellow = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect],
      );
      expect(yellow.pdfColour, '1 1 0');
    });

    test('handles a non-primary colour', () {
      const teal = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect],
        colorArgb: 0xFF008080,
      );
      final parts = teal.pdfColour.split(' ').map(double.parse).toList();
      expect(parts[0], 0);
      expect(parts[1], closeTo(0.502, 0.01));
      expect(parts[2], closeTo(0.502, 0.01));
    });
  });
}
