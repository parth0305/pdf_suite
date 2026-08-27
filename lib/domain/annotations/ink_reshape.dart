import 'dart:math' as math;

import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// Which point of which stroke, in a drawn annotation.
class InkPointRef {
  const InkPointRef({required this.stroke, required this.point});

  final int stroke;
  final int point;

  @override
  bool operator ==(Object other) =>
      other is InkPointRef && other.stroke == stroke && other.point == point;

  @override
  int get hashCode => Object.hash(stroke, point);
}

/// The point of [strokes] nearest [target], or null when none is near enough.
///
/// [toleranceP] is in PDF points and should come from the current zoom: a
/// tolerance fixed in document units is a huge grab area when zoomed in and an
/// unusable one when zoomed out.
InkPointRef? nearestInkPoint(
  List<List<PdfPoint>> strokes,
  PdfPoint target, {
  required double tolerancePt,
}) {
  InkPointRef? best;
  var bestDistance = double.infinity;

  for (var s = 0; s < strokes.length; s++) {
    for (var p = 0; p < strokes[s].length; p++) {
      final point = strokes[s][p];
      final distance = math.sqrt(
        math.pow(point.x - target.x, 2) + math.pow(point.y - target.y, 2),
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        best = InkPointRef(stroke: s, point: p);
      }
    }
  }

  return bestDistance <= tolerancePt ? best : null;
}

/// [strokes] with one point moved to [to].
///
/// Returns the input unchanged when the reference points at nothing, rather
/// than throwing: a stale handle after an undo is a normal thing to happen,
/// not an error.
List<List<PdfPoint>> withMovedPoint(
  List<List<PdfPoint>> strokes,
  InkPointRef ref,
  PdfPoint to,
) {
  if (ref.stroke < 0 || ref.stroke >= strokes.length) return strokes;
  if (ref.point < 0 || ref.point >= strokes[ref.stroke].length) return strokes;

  return [
    for (var s = 0; s < strokes.length; s++)
      [
        for (var p = 0; p < strokes[s].length; p++)
          s == ref.stroke && p == ref.point ? to : strokes[s][p],
      ],
  ];
}

/// The bounding box of [strokes], padded by half the stroke width.
///
/// The /Rect has to follow the points. A rectangle left where it was clips the
/// appearance, so a reshaped stroke would be drawn and then cut off - which
/// looks like the reshape failed rather than like a stale rectangle.
TextRect boundsOf(List<List<PdfPoint>> strokes, {double strokeWidth = 2}) {
  var left = double.infinity;
  var right = double.negativeInfinity;
  var top = double.negativeInfinity;
  var bottom = double.infinity;

  for (final stroke in strokes) {
    for (final p in stroke) {
      left = math.min(left, p.x);
      right = math.max(right, p.x);
      top = math.max(top, p.y);
      bottom = math.min(bottom, p.y);
    }
  }

  if (left > right) return const TextRect(left: 0, top: 0, right: 0, bottom: 0);

  final pad = strokeWidth / 2 + 1;
  return TextRect(
    left: left - pad,
    right: right + pad,
    top: top + pad,
    bottom: bottom - pad,
  );
}

/// A reshaped annotation, ready for the writer.
class InkReshape {
  const InkReshape({required this.strokes, required this.rect});

  final List<List<PdfPoint>> strokes;
  final TextRect rect;
}

/// Moves one point and recomputes the rectangle around the result.
InkReshape? reshapeInk(
  DrawingAnnotation annotation,
  InkPointRef ref,
  PdfPoint to,
) {
  final moved = withMovedPoint(annotation.strokes, ref, to);
  if (identical(moved, annotation.strokes)) return null;

  return InkReshape(
    strokes: moved,
    rect: boundsOf(moved, strokeWidth: annotation.strokeWidth),
  );
}
