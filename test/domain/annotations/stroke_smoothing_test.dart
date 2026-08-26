import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/stroke_smoothing.dart';

void main() {
  group('thinSamples', () {
    test('an empty stroke stays empty', () {
      expect(thinSamples(const []), isEmpty);
    });

    test('a single point survives', () {
      expect(thinSamples(const [PdfPoint(10, 10)]), hasLength(1));
    });

    // A finger held still emits dozens of near-identical samples.
    test('samples closer than the minimum distance are dropped', () {
      final raw = [
        const PdfPoint(10, 10),
        const PdfPoint(10.2, 10.1),
        const PdfPoint(10.3, 10.2),
        const PdfPoint(30, 10),
      ];
      final thinned = thinSamples(raw, minDistance: 2);

      expect(thinned, hasLength(2));
      expect(thinned.first, const PdfPoint(10, 10));
      expect(thinned.last, const PdfPoint(30, 10));
    });

    // Losing the final point would visibly shorten every stroke.
    test('the last point is always kept', () {
      final raw = [
        const PdfPoint(0, 0),
        const PdfPoint(50, 0),
        const PdfPoint(50.5, 0),
      ];
      expect(thinSamples(raw, minDistance: 5).last, const PdfPoint(50.5, 0));
    });

    test('widely spaced samples are all kept', () {
      final raw = [
        const PdfPoint(0, 0),
        const PdfPoint(20, 0),
        const PdfPoint(40, 0),
      ];
      expect(thinSamples(raw, minDistance: 2), hasLength(3));
    });
  });

  group('fitCurve', () {
    test('fewer than two points produce no segments', () {
      expect(fitCurve(const []), isEmpty);
      expect(fitCurve(const [PdfPoint(1, 1)]), isEmpty);
    });

    test('two points produce one segment ending at the second', () {
      final segments = fitCurve(const [PdfPoint(0, 0), PdfPoint(10, 0)]);

      expect(segments, hasLength(1));
      expect(segments.single.end, const PdfPoint(10, 0));
    });

    test('n points produce n-1 segments', () {
      final segments = fitCurve(const [
        PdfPoint(0, 0),
        PdfPoint(10, 10),
        PdfPoint(20, 0),
        PdfPoint(30, 10),
      ]);
      expect(segments, hasLength(3));
    });

    // The endpoints are what the user actually touched; they must not move.
    test('the curve ends exactly on the final point', () {
      const points = [PdfPoint(0, 0), PdfPoint(10, 20), PdfPoint(35, 5)];
      expect(fitCurve(points).last.end, const PdfPoint(35, 5));
    });

    test('a straight horizontal drag stays straight', () {
      const points = [PdfPoint(0, 0), PdfPoint(10, 0), PdfPoint(20, 0)];

      for (final segment in fitCurve(points)) {
        expect(segment.control1.y, closeTo(0, 0.001));
        expect(segment.control2.y, closeTo(0, 0.001));
        expect(segment.end.y, closeTo(0, 0.001));
      }
    });

    test('control points lie between their segment endpoints', () {
      const points = [PdfPoint(0, 0), PdfPoint(30, 0), PdfPoint(60, 0)];
      final first = fitCurve(points).first;

      expect(first.control1.x, inInclusiveRange(0, 30));
      expect(first.control2.x, inInclusiveRange(0, 30));
    });
  });
}
