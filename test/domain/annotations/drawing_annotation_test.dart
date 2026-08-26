import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

DrawingAnnotation drawing(DrawingKind kind, [List<PdfPoint>? points]) =>
    DrawingAnnotation(
      kind: kind,
      pageIndex: 0,
      strokes: [
        points ?? const [PdfPoint(10, 20), PdfPoint(50, 80)],
      ],
    );

void main() {
  group('pdfSubtype', () {
    test('ink is /Ink', () {
      expect(drawing(DrawingKind.ink).pdfSubtype, 'Ink');
    });

    test('rectangle is /Square', () {
      expect(drawing(DrawingKind.rectangle).pdfSubtype, 'Square');
    });

    // PDF's /Circle draws an ellipse inscribed in /Rect. The enum says what it
    // draws; the subtype says what the format calls it.
    test('ellipse is /Circle, because that is what PDF calls an oval', () {
      expect(drawing(DrawingKind.ellipse).pdfSubtype, 'Circle');
    });

    test('line is /Line', () {
      expect(drawing(DrawingKind.line).pdfSubtype, 'Line');
    });

    test('arrow is also /Line, distinguished by its line ending', () {
      expect(drawing(DrawingKind.arrow).pdfSubtype, 'Line');
    });
  });

  group('boundsPt', () {
    test('spans every point', () {
      final b = drawing(DrawingKind.ink, const [
        PdfPoint(10, 90),
        PdfPoint(70, 20),
        PdfPoint(40, 55),
      ]).boundsPt;

      expect(b.left, 10);
      expect(b.right, 70);
      expect(b.bottom, 20);
      expect(b.top, 90);
    });

    // A drag up-and-left must give the same rectangle as down-and-right, or
    // shapes drawn in three of the four directions would be inside out.
    test('a reversed drag produces the same rectangle', () {
      final forward = drawing(DrawingKind.rectangle, const [
        PdfPoint(10, 20),
        PdfPoint(50, 80),
      ]).boundsPt;
      final reverse = drawing(DrawingKind.rectangle, const [
        PdfPoint(50, 80),
        PdfPoint(10, 20),
      ]).boundsPt;

      expect(reverse.left, forward.left);
      expect(reverse.right, forward.right);
      expect(reverse.bottom, forward.bottom);
      expect(reverse.top, forward.top);
    });

    test('a single point produces a degenerate rectangle, not a crash', () {
      final b = drawing(DrawingKind.ink, const [PdfPoint(10, 10)]).boundsPt;
      expect(b.left, 10);
      expect(b.right, 10);
    });
  });

  group('pdfColour', () {
    test('black is 0 0 0', () {
      expect(drawing(DrawingKind.ink).pdfColour, '0 0 0');
    });

    test('a red stroke converts to components in 0..1', () {
      const red = DrawingAnnotation(
        kind: DrawingKind.ink,
        pageIndex: 0,
        strokes: [
          [PdfPoint(0, 0), PdfPoint(1, 1)],
        ],
        colorArgb: 0xFFFF0000,
      );
      expect(red.pdfColour, '1 0 0');
    });
  });

  group('the sealed hierarchy', () {
    test('both kinds are Annotations', () {
      expect(drawing(DrawingKind.ink), isA<Annotation>());
      expect(
        const TextMarkup(
          kind: MarkupKind.highlight,
          pageIndex: 0,
          quads: [TextRect(left: 0, top: 10, right: 10, bottom: 0)],
        ),
        isA<Annotation>(),
      );
    });

    test('a list can hold both', () {
      final list = <Annotation>[
        drawing(DrawingKind.ink),
        const TextMarkup(
          kind: MarkupKind.underline,
          pageIndex: 1,
          quads: [TextRect(left: 0, top: 10, right: 10, bottom: 0)],
        ),
      ];
      expect(list.map((a) => a.pageIndex), [0, 1]);
      expect(list.map((a) => a.pdfSubtype), ['Ink', 'Underline']);
    });
  });
}
