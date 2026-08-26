import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/domain/signatures/signature_geometry.dart';

SavedSignature sig(List<List<PdfPoint>> strokes, double aspect) =>
    SavedSignature(id: 1, label: 'Full', strokes: strokes, aspectRatio: aspect);

void main() {
  group('normaliseStrokes', () {
    test('maps captured strokes into a unit box', () {
      final result = normaliseStrokes(const [
        [PdfPoint(100, 200), PdfPoint(300, 400)],
      ]);

      final flat = result.strokes.expand((s) => s).toList();
      expect(flat.every((p) => p.x >= 0 && p.x <= 1), isTrue);
      expect(flat.every((p) => p.y >= 0 && p.y <= 1), isTrue);
      expect(flat.first.x, 0);
      expect(flat.last.x, 1);
    });

    test('keeps stroke boundaries', () {
      final result = normaliseStrokes(const [
        [PdfPoint(0, 0), PdfPoint(10, 10)],
        [PdfPoint(20, 0), PdfPoint(30, 10)],
      ]);

      expect(result.strokes, hasLength(2));
    });

    test('reports the aspect ratio of a wide capture', () {
      final result = normaliseStrokes(const [
        [PdfPoint(0, 0), PdfPoint(200, 50)],
      ]);

      expect(result.aspectRatio, closeTo(4, 0.001));
    });

    test('reports the aspect ratio of a tall capture', () {
      final result = normaliseStrokes(const [
        [PdfPoint(0, 0), PdfPoint(50, 200)],
      ]);

      expect(result.aspectRatio, closeTo(0.25, 0.001));
    });

    // A perfectly horizontal stroke has zero height. Dividing by it would
    // produce NaN coordinates and an annotation that renders nowhere.
    test('a zero-height capture does not divide by zero', () {
      final result = normaliseStrokes(const [
        [PdfPoint(0, 50), PdfPoint(100, 50)],
      ]);

      final flat = result.strokes.expand((s) => s).toList();
      expect(flat.every((p) => p.y.isFinite), isTrue);
      expect(result.aspectRatio.isFinite, isTrue);
    });

    test('a single point does not divide by zero', () {
      final result = normaliseStrokes(const [
        [PdfPoint(5, 5)],
      ]);

      expect(result.strokes.single.single.x.isFinite, isTrue);
    });
  });

  group('placeSignature', () {
    final wide = sig(const [
      [PdfPoint(0, 0), PdfPoint(1, 1)],
    ], 2);

    test('fits inside the box', () {
      final placed = placeSignature(
        wide,
        box: const TextRect(left: 100, bottom: 100, right: 300, top: 300),
      );

      final flat = placed.expand((s) => s).toList();
      expect(flat.every((p) => p.x >= 100 && p.x <= 300), isTrue);
      expect(flat.every((p) => p.y >= 100 && p.y <= 300), isTrue);
    });

    // A stretched signature looks forged.
    test('preserves aspect ratio in a box taller than the signature', () {
      final placed = placeSignature(
        wide,
        box: const TextRect(left: 0, bottom: 0, right: 200, top: 200),
      );

      final flat = placed.expand((s) => s).toList();
      final width = flat.last.x - flat.first.x;
      final height = flat.last.y - flat.first.y;
      expect(width / height, closeTo(2, 0.001));
    });

    test('preserves aspect ratio in a box wider than the signature', () {
      final placed = placeSignature(
        wide,
        box: const TextRect(left: 0, bottom: 0, right: 400, top: 100),
      );

      final flat = placed.expand((s) => s).toList();
      final width = flat.last.x - flat.first.x;
      final height = flat.last.y - flat.first.y;
      expect(width / height, closeTo(2, 0.001));
    });

    test('centres the signature within the box', () {
      final placed = placeSignature(
        wide,
        box: const TextRect(left: 0, bottom: 0, right: 200, top: 200),
      );

      final flat = placed.expand((s) => s).toList();
      final top = flat.map((p) => p.y).reduce((a, b) => a > b ? a : b);
      final bottom = flat.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      expect((top + bottom) / 2, closeTo(100, 0.001));
    });

    // Stored strokes are y-up, like PDF. Flipping here puts every signature
    // upside down.
    test('does not flip the y axis', () {
      final placed = placeSignature(
        sig(const [
          [PdfPoint(0, 0), PdfPoint(1, 1)],
        ], 1),
        box: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
      );

      expect(placed.single.last.y, greaterThan(placed.single.first.y));
    });

    test('keeps stroke boundaries', () {
      final placed = placeSignature(
        sig(const [
          [PdfPoint(0, 0), PdfPoint(0.4, 1)],
          [PdfPoint(0.6, 0), PdfPoint(1, 1)],
        ], 1),
        box: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
      );

      expect(placed, hasLength(2));
    });
  });
}
