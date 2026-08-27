import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/ink_reshape.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

List<List<PdfPoint>> twoStrokes() => [
  [const PdfPoint(10, 10), const PdfPoint(20, 20), const PdfPoint(30, 10)],
  [const PdfPoint(100, 100), const PdfPoint(110, 110)],
];

DrawingAnnotation inkOf() => DrawingAnnotation(
  kind: DrawingKind.ink,
  pageIndex: 0,
  strokes: twoStrokes(),
  colorArgb: 0xFF000000,
  strokeWidth: 4,
);

void main() {
  group('finding a point', () {
    test('the nearest point is found', () {
      final ref = nearestInkPoint(
        twoStrokes(),
        const PdfPoint(21, 19),
        tolerancePt: 5,
      );

      expect(ref, const InkPointRef(stroke: 0, point: 1));
    });

    test('points in a later stroke are reachable', () {
      final ref = nearestInkPoint(
        twoStrokes(),
        const PdfPoint(109, 111),
        tolerancePt: 5,
      );

      expect(ref, const InkPointRef(stroke: 1, point: 1));
    });

    // Without a tolerance every tap anywhere would grab the nearest point,
    // and dragging the page would drag a stroke instead.
    test('a tap far from every point grabs nothing', () {
      expect(
        nearestInkPoint(twoStrokes(), const PdfPoint(500, 500), tolerancePt: 5),
        isNull,
      );
    });

    test('the tolerance is honoured exactly', () {
      const target = PdfPoint(10, 15);

      expect(
        nearestInkPoint(twoStrokes(), target, tolerancePt: 5),
        isNotNull,
        reason: 'exactly 5 away',
      );
      expect(nearestInkPoint(twoStrokes(), target, tolerancePt: 4.9), isNull);
    });

    test('no strokes yields nothing', () {
      expect(
        nearestInkPoint(const [], const PdfPoint(0, 0), tolerancePt: 100),
        isNull,
      );
    });
  });

  group('moving a point', () {
    test('only the chosen point moves', () {
      final moved = withMovedPoint(
        twoStrokes(),
        const InkPointRef(stroke: 0, point: 1),
        const PdfPoint(25, 40),
      );

      expect(moved[0][1], const PdfPoint(25, 40));
      expect(moved[0][0], const PdfPoint(10, 10));
      expect(moved[0][2], const PdfPoint(30, 10));
      expect(moved[1], twoStrokes()[1], reason: 'the other stroke is intact');
    });

    test('stroke boundaries survive', () {
      final moved = withMovedPoint(
        twoStrokes(),
        const InkPointRef(stroke: 1, point: 0),
        const PdfPoint(0, 0),
      );

      expect(moved, hasLength(2));
      expect(moved[0], hasLength(3));
      expect(moved[1], hasLength(2));
    });

    // A stale handle after an undo is normal, not an error.
    test('a reference to nothing leaves the strokes alone', () {
      final original = twoStrokes();

      expect(
        withMovedPoint(
          original,
          const InkPointRef(stroke: 9, point: 0),
          const PdfPoint(1, 1),
        ),
        same(original),
      );
      expect(
        withMovedPoint(
          original,
          const InkPointRef(stroke: 0, point: 99),
          const PdfPoint(1, 1),
        ),
        same(original),
      );
    });
  });

  group('the rectangle follows the points', () {
    // A /Rect left where it was CLIPS the appearance, so the reshaped stroke
    // is drawn and then cut off - which looks like the reshape failed.
    test('it grows when a point moves outside', () {
      final reshaped = reshapeInk(
        inkOf(),
        const InkPointRef(stroke: 1, point: 1),
        const PdfPoint(400, 400),
      )!;

      expect(reshaped.rect.right, greaterThan(400));
      expect(reshaped.rect.top, greaterThan(400));
    });

    test('it shrinks when the outlying point comes back', () {
      final reshaped = reshapeInk(
        inkOf(),
        const InkPointRef(stroke: 1, point: 1),
        const PdfPoint(30, 30),
      )!;

      expect(reshaped.rect.right, lessThan(120));
    });

    // Half the stroke width plus a point: a rect drawn exactly on the
    // outermost points clips the pen's own thickness.
    test('it is padded by half the stroke width', () {
      final bounds = boundsOf(twoStrokes(), strokeWidth: 4);

      // A rect drawn exactly on the outermost points clips the pen's own
      // thickness, so the padding is half the width plus a point.
      expect(bounds.left, 10 - 3);
      expect(bounds.top, 110 + 3);
    });

    // Null means "that reference points at nothing", not "the geometry did
    // not change" - a caller distinguishing those would be reading intent
    // into a no-op.
    test('an invalid reference reshapes nothing', () {
      expect(
        reshapeInk(
          inkOf(),
          const InkPointRef(stroke: 7, point: 0),
          const PdfPoint(1, 1),
        ),
        isNull,
      );
    });

    test('a valid reference always reshapes, even to the same place', () {
      expect(
        reshapeInk(
          inkOf(),
          const InkPointRef(stroke: 0, point: 0),
          const PdfPoint(10, 10),
        ),
        isNotNull,
      );
    });

    test('empty strokes give an empty rect rather than infinities', () {
      final bounds = boundsOf(const []);

      expect(bounds.left, 0);
      expect(bounds.right, 0);
      expect(bounds.width, 0);
    });
  });
}
