import 'dart:math' as math;

import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart' show pdfNumber;
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/stroke_smoothing.dart';

/// Magic constant for approximating a quarter ellipse with a cubic Bezier.
/// PDF has no ellipse operator, so four of these make an oval.
const double _kappa = 0.5523;

/// Content stream drawing this annotation's appearance.
String drawingAppearanceStream(DrawingAnnotation drawing) {
  final b = drawing.boundsPt;
  final buffer = StringBuffer()
    ..writeln('${drawing.pdfColour} RG')
    ..writeln('${pdfNumber(drawing.strokeWidth)} w')
    // Round caps and joins: without them a freehand stroke reads as a chain of
    // straight segments with visible corners.
    ..writeln('1 J')
    ..writeln('1 j');

  switch (drawing.kind) {
    case DrawingKind.ink:
      if (drawing.points.length < 2) return buffer.toString();
      final first = drawing.points.first;
      buffer.writeln('${pdfNumber(first.x)} ${pdfNumber(first.y)} m');
      for (final s in fitCurve(drawing.points)) {
        buffer.writeln(
          '${pdfNumber(s.control1.x)} ${pdfNumber(s.control1.y)} '
          '${pdfNumber(s.control2.x)} ${pdfNumber(s.control2.y)} '
          '${pdfNumber(s.end.x)} ${pdfNumber(s.end.y)} c',
        );
      }
      buffer.writeln('S');

    case DrawingKind.rectangle:
      buffer.writeln(
        '${pdfNumber(b.left)} ${pdfNumber(b.bottom)} '
        '${pdfNumber(b.right - b.left)} ${pdfNumber(b.top - b.bottom)} re',
      );
      buffer.writeln('S');

    case DrawingKind.ellipse:
      _writeEllipse(buffer, b);
      buffer.writeln('S');

    case DrawingKind.line:
      final a = drawing.points.first;
      final z = drawing.points.last;
      buffer.writeln('${pdfNumber(a.x)} ${pdfNumber(a.y)} m');
      buffer.writeln('${pdfNumber(z.x)} ${pdfNumber(z.y)} l');
      buffer.writeln('S');

    case DrawingKind.arrow:
      final a = drawing.points.first;
      final z = drawing.points.last;
      buffer.writeln('${pdfNumber(a.x)} ${pdfNumber(a.y)} m');
      buffer.writeln('${pdfNumber(z.x)} ${pdfNumber(z.y)} l');
      _writeArrowHead(buffer, a, z, drawing.strokeWidth);
      buffer.writeln('S');
  }

  return buffer.toString();
}

void _writeEllipse(
  StringBuffer buffer,
  ({double left, double bottom, double right, double top}) b,
) {
  final cx = (b.left + b.right) / 2;
  final cy = (b.bottom + b.top) / 2;
  final rx = (b.right - b.left) / 2;
  final ry = (b.top - b.bottom) / 2;
  final ox = rx * _kappa;
  final oy = ry * _kappa;

  String n(double v) => pdfNumber(v);

  buffer.writeln('${n(cx - rx)} ${n(cy)} m');
  buffer.writeln(
    '${n(cx - rx)} ${n(cy + oy)} ${n(cx - ox)} ${n(cy + ry)} '
    '${n(cx)} ${n(cy + ry)} c',
  );
  buffer.writeln(
    '${n(cx + ox)} ${n(cy + ry)} ${n(cx + rx)} ${n(cy + oy)} '
    '${n(cx + rx)} ${n(cy)} c',
  );
  buffer.writeln(
    '${n(cx + rx)} ${n(cy - oy)} ${n(cx + ox)} ${n(cy - ry)} '
    '${n(cx)} ${n(cy - ry)} c',
  );
  buffer.writeln(
    '${n(cx - ox)} ${n(cy - ry)} ${n(cx - rx)} ${n(cy - oy)} '
    '${n(cx - rx)} ${n(cy)} c',
  );
}

/// Two short strokes back from the tip, forming a V.
void _writeArrowHead(
  StringBuffer buffer,
  PdfPoint from,
  PdfPoint to,
  double strokeWidth,
) {
  final angle = math.atan2(to.y - from.y, to.x - from.x);
  final length = math.max(8.0, strokeWidth * 4);
  const spread = 0.5; // radians either side of the shaft

  for (final side in [angle + math.pi - spread, angle + math.pi + spread]) {
    buffer.writeln('${pdfNumber(to.x)} ${pdfNumber(to.y)} m');
    buffer.writeln(
      '${pdfNumber(to.x + length * math.cos(side))} '
      '${pdfNumber(to.y + length * math.sin(side))} l',
    );
  }
}

/// The form XObject dictionary wrapping [drawingAppearanceStream].
String drawingAppearanceDict(DrawingAnnotation drawing, int streamLength) {
  final b = drawing.boundsPt;
  // Grow by half the stroke width: a stroke straddles its path, so a tight
  // BBox would clip the outer half of every edge.
  final pad = drawing.strokeWidth / 2;
  final bbox =
      '[${pdfNumber(b.left - pad)} ${pdfNumber(b.bottom - pad)} '
      '${pdfNumber(b.right + pad)} ${pdfNumber(b.top + pad)}]';

  return '<< /Type /XObject /Subtype /Form /BBox $bbox '
      '/Resources << >> /Length $streamLength >>';
}
