import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

/// An A4 page drawn at 1x: 595x842pt shown as 595x842 logical pixels at the
/// canvas origin.
const a4At1x = Rect.fromLTWH(0, 0, 595, 842);
const w = 595.0;
const h = 842.0;

void main() {
  group('canvasToPdf', () {
    // The whole point of this file. PDF y grows upward; canvas y grows
    // downward. Near the TOP of the page, PDF y must be LARGE.
    test('a point near the page top maps to a large PDF y', () {
      final p = canvasToPdf(
        const Offset(100, 10),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.y, greaterThan(800), reason: 'y-up: near the top means high y');
    });

    test('a point near the page bottom maps to a small PDF y', () {
      final p = canvasToPdf(
        const Offset(100, 832),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.y, lessThan(20));
    });

    test('the top-left canvas corner is the top-left of PDF space', () {
      final p = canvasToPdf(
        Offset.zero,
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.x, closeTo(0, 0.001));
      expect(p.y, closeTo(842, 0.001));
    });

    test('the bottom-right canvas corner is the PDF origin corner', () {
      final p = canvasToPdf(
        const Offset(595, 842),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.x, closeTo(595, 0.001));
      expect(p.y, closeTo(0, 0.001));
    });

    test('x is unaffected by the flip', () {
      final p = canvasToPdf(
        const Offset(300, 400),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.x, closeTo(300, 0.001));
    });
  });

  group('round trip', () {
    void roundTrips(String label, Rect rect) {
      test('survives a round trip $label', () {
        for (final point in const [
          Offset(0, 0),
          Offset(1, 1),
          Offset(123.5, 456.25),
          Offset(300, 400),
        ]) {
          final canvas = Offset(
            rect.left + point.dx * (rect.width / w),
            rect.top + point.dy * (rect.height / h),
          );
          final pdf = canvasToPdf(
            canvas,
            pageRect: rect,
            pageWidthPt: w,
            pageHeightPt: h,
          );
          final back = pdfToCanvas(
            pdf,
            pageRect: rect,
            pageWidthPt: w,
            pageHeightPt: h,
          );

          expect(back.dx, closeTo(canvas.dx, 0.01), reason: '$label x');
          expect(back.dy, closeTo(canvas.dy, 0.01), reason: '$label y');
        }
      });
    }

    roundTrips('at 1x', a4At1x);
    roundTrips('at 2.5x zoom', const Rect.fromLTWH(0, 0, 1487.5, 2105));
    roundTrips('at 0.4x zoom', const Rect.fromLTWH(0, 0, 238, 336.8));
    // A page scrolled partly out of view has a negative origin.
    roundTrips(
      'scrolled off-screen',
      const Rect.fromLTWH(-200, -350, 595, 842),
    );
    roundTrips(
      'offset and zoomed',
      const Rect.fromLTWH(37.5, -120, 892.5, 1263),
    );
  });

  group('zoom independence', () {
    // The same physical spot on the page must yield the same PDF point at any
    // zoom, or strokes would land differently depending on how far you had
    // pinched in.
    test('the page centre maps identically at 1x and 2.5x', () {
      final at1x = canvasToPdf(
        const Offset(297.5, 421),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      final at2x = canvasToPdf(
        const Offset(743.75, 1052.5),
        pageRect: const Rect.fromLTWH(0, 0, 1487.5, 2105),
        pageWidthPt: w,
        pageHeightPt: h,
      );

      expect(at2x.x, closeTo(at1x.x, 0.01));
      expect(at2x.y, closeTo(at1x.y, 0.01));
    });
  });

  group('PdfPoint', () {
    test('points with the same coordinates are equal', () {
      expect(const PdfPoint(1.5, 2.5), const PdfPoint(1.5, 2.5));
      expect(
        const PdfPoint(1.5, 2.5).hashCode,
        const PdfPoint(1.5, 2.5).hashCode,
      );
    });

    test('points with different coordinates are not equal', () {
      expect(const PdfPoint(1, 2), isNot(const PdfPoint(2, 1)));
    });
  });
}
