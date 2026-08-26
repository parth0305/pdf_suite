import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

/// Tap a spot on the page to place something there.
///
/// One surface serves both the note and stamp modes; the mode decides what
/// [onTap] does. Present only inside those modes, so it cannot compete with
/// the viewer for scroll or pinch.
class TapPlacementSurface extends ConsumerWidget {
  const TapPlacementSurface({
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.pageIndex,
    required this.onTap,
    super.key,
  });

  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;
  final int pageIndex;
  final void Function(PdfPoint) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staged = ref
        .watch(annotationSessionProvider)
        .session
        .annotationsOnPage(pageIndex);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => onTap(
        canvasToPdf(
          d.localPosition,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _StagedPainter(
          annotations: staged,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
    );
  }
}

/// Previews what is staged but not yet saved, so the user can see it before
/// committing.
class _StagedPainter extends CustomPainter {
  const _StagedPainter({
    required this.annotations,
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final List<Annotation> annotations;
  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;

  Offset _at(PdfPoint p) => pdfToCanvas(
    p,
    pageRect: pageRect,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );

  double get _scale => pageRect.width / pageWidthPt;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in annotations) {
      switch (a) {
        case StickyNote():
          final origin = _at(a.anchorPt);
          final side = StickyNote.iconSizePt * _scale;
          final rect = Rect.fromLTWH(origin.dx, origin.dy, side, side);
          canvas
            ..drawRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(3)),
              Paint()..color = Color(a.colorArgb),
            )
            ..drawRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(3)),
              Paint()
                ..color = const Color(0xFF000000)
                ..strokeWidth = 1
                ..style = PaintingStyle.stroke,
            );

        case Stamp():
          final origin = _at(a.anchorPt);
          final rect = Rect.fromLTWH(
            origin.dx,
            origin.dy,
            a.widthPt * _scale,
            a.heightPt * _scale,
          );
          canvas.drawRect(
            rect,
            Paint()
              ..color = Color(a.colorArgb)
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke,
          );
          final painter = TextPainter(
            text: TextSpan(
              text: a.label,
              style: TextStyle(
                color: Color(a.colorArgb),
                fontSize: Stamp.fontSizePt * _scale,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(
            canvas,
            Offset(
              rect.left + Stamp.paddingPt * _scale,
              rect.top + Stamp.paddingPt * _scale,
            ),
          );

        case TextMarkup():
        case DrawingAnnotation():
          break;
      }
    }
  }

  @override
  bool shouldRepaint(_StagedPainter old) =>
      old.annotations.length != annotations.length || old.pageRect != pageRect;
}
