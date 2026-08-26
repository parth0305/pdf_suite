import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/drawing_appearance.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

DrawingAnnotation of(DrawingKind kind, [List<PdfPoint>? pts]) =>
    DrawingAnnotation(
      kind: kind,
      pageIndex: 0,
      strokes: [
        pts ?? const [PdfPoint(10, 20), PdfPoint(50, 80)],
      ],
      strokeWidth: 3,
    );

void main() {
  group('stroke settings', () {
    test('the stroke width is emitted', () {
      expect(drawingAppearanceStream(of(DrawingKind.line)), contains('3 w'));
    });

    test('the colour is emitted as a stroking colour', () {
      expect(
        drawingAppearanceStream(of(DrawingKind.line)),
        contains('0 0 0 RG'),
      );
    });

    // Round caps and joins are what make a freehand stroke look like ink
    // rather than a chain of segments.
    test('ink uses round caps and joins', () {
      final s = drawingAppearanceStream(
        of(DrawingKind.ink, const [
          PdfPoint(0, 0),
          PdfPoint(10, 10),
          PdfPoint(20, 0),
        ]),
      );
      expect(s, contains('1 J'));
      expect(s, contains('1 j'));
    });
  });

  group('ink', () {
    test('moves to the first point then emits curves', () {
      final s = drawingAppearanceStream(
        of(DrawingKind.ink, const [
          PdfPoint(0, 0),
          PdfPoint(10, 10),
          PdfPoint(20, 0),
        ]),
      );

      expect(s, contains('0 0 m'));
      expect(s, contains('c'));
      expect(s, contains('S'));
    });

    test('a two-point stroke still produces a path', () {
      final s = drawingAppearanceStream(
        of(DrawingKind.ink, const [PdfPoint(0, 0), PdfPoint(10, 0)]),
      );
      expect(s, contains('m'));
      expect(s, contains('S'));
    });

    test('a single-point stroke produces no path rather than crashing', () {
      final s = drawingAppearanceStream(
        of(DrawingKind.ink, const [PdfPoint(5, 5)]),
      );
      expect(s, isNot(contains('c')));
    });
  });

  group('shapes', () {
    test('rectangle emits a stroked re', () {
      final s = drawingAppearanceStream(of(DrawingKind.rectangle));
      expect(s, contains('re'));
      expect(s, contains('S'));
      expect(s, contains('10 20 40 60 re'), reason: 'x y width height');
    });

    // PDF has no ellipse operator; four Bezier arcs approximate one.
    test('ellipse emits four curves, not a rectangle', () {
      final s = drawingAppearanceStream(of(DrawingKind.ellipse));
      expect('c'.allMatches(s).length, greaterThanOrEqualTo(4));
      expect(s, isNot(contains(' re')));
    });

    test('line emits a move and a lineto', () {
      final s = drawingAppearanceStream(of(DrawingKind.line));
      expect(s, contains('10 20 m'));
      expect(s, contains('50 80 l'));
    });

    // An arrow is a line plus a head; without the extra strokes it is just a
    // line and the tool would appear broken.
    test('arrow emits more path segments than a plain line', () {
      final line = 'l'
          .allMatches(drawingAppearanceStream(of(DrawingKind.line)))
          .length;
      final arrow = 'l'
          .allMatches(drawingAppearanceStream(of(DrawingKind.arrow)))
          .length;
      expect(arrow, greaterThan(line));
    });
  });

  group('drawingAppearanceDict', () {
    test(
      'is a form XObject whose BBox covers the drawing plus stroke width',
      () {
        final d = drawingAppearanceDict(of(DrawingKind.rectangle), 42);

        expect(d, contains('/Type /XObject'));
        expect(d, contains('/Subtype /Form'));
        expect(d, contains('/Length 42'));
        // Bounds 10,20..50,80 grown by half the 3pt stroke.
        expect(d, contains('/BBox [8.5 18.5 51.5 81.5]'));
      },
    );

    test('a zero-area drawing still gets a non-degenerate BBox', () {
      final d = drawingAppearanceDict(
        of(DrawingKind.ink, const [PdfPoint(10, 10), PdfPoint(10, 10)]),
        10,
      );
      expect(d, contains('/BBox'));
    });
  });
}
