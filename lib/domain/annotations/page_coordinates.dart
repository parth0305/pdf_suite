import 'dart:ui';

import 'package:folio/domain/annotations/pdf_point.dart';

/// Converts a point in canvas space to PDF user space.
///
/// [pageRect] is where the page is currently drawn on the canvas, which is what
/// pdfrx's page paint callback supplies. It already encodes zoom and scroll, so
/// no separate zoom factor is needed.
///
/// Canvas y grows downward; PDF y grows upward. The flip is the entire reason
/// this function exists as a tested unit.
PdfPoint canvasToPdf(
  Offset canvasPoint, {
  required Rect pageRect,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final normalisedX = (canvasPoint.dx - pageRect.left) / pageRect.width;
  final normalisedY = (canvasPoint.dy - pageRect.top) / pageRect.height;

  return PdfPoint(normalisedX * pageWidthPt, (1 - normalisedY) * pageHeightPt);
}

/// The inverse of [canvasToPdf], used to preview staged drawings on screen.
Offset pdfToCanvas(
  PdfPoint point, {
  required Rect pageRect,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final normalisedX = point.x / pageWidthPt;
  final normalisedY = 1 - (point.y / pageHeightPt);

  return Offset(
    pageRect.left + normalisedX * pageRect.width,
    pageRect.top + normalisedY * pageRect.height,
  );
}
