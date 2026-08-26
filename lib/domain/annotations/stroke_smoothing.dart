import 'dart:math' as math;

import 'package:folio/domain/annotations/pdf_point.dart';

/// One cubic Bezier segment. The start point is the previous segment's end, or
/// the path's initial `m` for the first segment.
class CubicSegment {
  const CubicSegment({
    required this.control1,
    required this.control2,
    required this.end,
  });

  final PdfPoint control1;
  final PdfPoint control2;
  final PdfPoint end;
}

/// Drops samples closer together than [minDistance].
///
/// A finger held still emits dozens of near-identical points; keeping them all
/// bloats /InkList and gains nothing visible. The final point is always kept,
/// because dropping it visibly shortens the stroke.
List<PdfPoint> thinSamples(List<PdfPoint> raw, {double minDistance = 2.0}) {
  if (raw.length < 2) return List.of(raw);

  final kept = <PdfPoint>[raw.first];
  for (final point in raw.skip(1)) {
    final last = kept.last;
    final dx = point.x - last.x;
    final dy = point.y - last.y;
    if (math.sqrt(dx * dx + dy * dy) >= minDistance) kept.add(point);
  }

  // Preserve the true end of the stroke even if it was too close to keep.
  if (kept.last != raw.last) kept.add(raw.last);
  return kept;
}

/// Fits a smooth curve through [points] as cubic Bezier segments.
///
/// Uses Catmull-Rom tangents converted to Bezier control points, which passes
/// exactly through every input point - important because those are the
/// positions the user actually touched.
List<CubicSegment> fitCurve(List<PdfPoint> points) {
  if (points.length < 2) return const [];

  final segments = <CubicSegment>[];
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = i == 0 ? points[i] : points[i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = i + 2 < points.length ? points[i + 2] : p2;

    // Catmull-Rom to Bezier: control points sit one sixth of the neighbouring
    // span away from each endpoint.
    segments.add(
      CubicSegment(
        control1: PdfPoint(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6),
        control2: PdfPoint(p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6),
        end: p2,
      ),
    );
  }
  return segments;
}
