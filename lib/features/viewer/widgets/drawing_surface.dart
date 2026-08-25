import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

/// Captures strokes over the page and previews them.
///
/// Sits above the viewer only in drawing mode: in read mode it is absent
/// entirely, so it can never intercept a scroll or a pinch.
///
/// The preview and the written annotation derive from the same points - the
/// preview converts staged PDF points back to canvas space rather than keeping
/// a second copy, so what the user sees is what gets written.
class DrawingSurface extends ConsumerWidget {
  const DrawingSurface({
    required this.tool,
    required this.colorArgb,
    required this.strokeWidth,
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.pageIndex,
    super.key,
  });

  final DrawingKind tool;
  final int colorArgb;
  final double strokeWidth;

  /// Where the page sits in this widget's own coordinate space.
  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;
  final int pageIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(annotationSessionProvider);
    final controller = ref.read(annotationSessionProvider.notifier);

    final staged = state.session
        .annotationsOnPage(pageIndex)
        .whereType<DrawingAnnotation>()
        .toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => controller.beginStroke(d.localPosition),
      onPanUpdate: (d) => controller.extendStroke(d.localPosition),
      onPanEnd: (_) => controller.endStroke(
        tool: tool,
        pageIndex: pageIndex,
        pageRect: pageRect,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
        colorArgb: colorArgb,
        strokeWidth: strokeWidth,
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _DrawingPainter(
          live: state.liveStroke,
          staged: staged,
          tool: tool,
          colorArgb: colorArgb,
          strokeWidth: strokeWidth,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  const _DrawingPainter({
    required this.live,
    required this.staged,
    required this.tool,
    required this.colorArgb,
    required this.strokeWidth,
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final List<Offset> live;
  final List<DrawingAnnotation> staged;
  final DrawingKind tool;
  final int colorArgb;
  final double strokeWidth;
  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;

  Offset _toCanvas(PdfPoint p) => pdfToCanvas(
    p,
    pageRect: pageRect,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );

  Paint _paint(int argb, double width) => Paint()
    ..color = Color(argb)
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
    // Matches the round caps and joins the appearance stream emits.
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    for (final drawing in staged) {
      _drawShape(
        canvas,
        drawing.kind,
        drawing.points.map(_toCanvas).toList(),
        _paint(drawing.colorArgb, drawing.strokeWidth),
      );
    }

    if (live.length >= 2) {
      final points = tool == DrawingKind.ink ? live : [live.first, live.last];
      _drawShape(canvas, tool, points, _paint(colorArgb, strokeWidth));
    }
  }

  void _drawShape(
    Canvas canvas,
    DrawingKind kind,
    List<Offset> points,
    Paint paint,
  ) {
    if (points.length < 2) return;

    switch (kind) {
      case DrawingKind.ink:
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final p in points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);

      case DrawingKind.rectangle:
        canvas.drawRect(Rect.fromPoints(points.first, points.last), paint);

      case DrawingKind.ellipse:
        canvas.drawOval(Rect.fromPoints(points.first, points.last), paint);

      case DrawingKind.line:
        canvas.drawLine(points.first, points.last, paint);

      case DrawingKind.arrow:
        canvas.drawLine(points.first, points.last, paint);
        _drawArrowHead(canvas, points.first, points.last, paint);
    }
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final angle = (to - from).direction;
    final length = strokeWidth * 4 < 8 ? 8.0 : strokeWidth * 4;
    const spread = 0.5;

    for (final side in [angle + 3.14159 - spread, angle + 3.14159 + spread]) {
      canvas.drawLine(to, to + Offset.fromDirection(side, length), paint);
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter old) =>
      old.live != live ||
      old.staged.length != staged.length ||
      old.tool != tool ||
      old.colorArgb != colorArgb ||
      old.strokeWidth != strokeWidth ||
      old.pageRect != pageRect;
}
