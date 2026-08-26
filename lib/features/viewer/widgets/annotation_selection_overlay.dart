import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/features/viewer/annotation_edit_providers.dart';

/// The object number of the annotation under [canvasPoint], or null.
///
/// Smallest area first: a large rectangle must not swallow the small highlight
/// drawn on top of it, which is what tapping the topmost match would do.
int? annotationAtPoint(
  Offset canvasPoint, {
  required List<SavedAnnotation> annotations,
  required Rect pageRect,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final candidates = annotations.where((a) {
    final rect = canvasRectOf(
      a,
      pageRect: pageRect,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
    );
    return rect.contains(canvasPoint);
  }).toList()..sort((a, b) => _areaOf(a).compareTo(_areaOf(b)));

  return candidates.isEmpty ? null : candidates.first.objectNumber;
}

double _areaOf(SavedAnnotation a) =>
    (a.rectPt.right - a.rectPt.left) * (a.rectPt.top - a.rectPt.bottom);

Rect canvasRectOf(
  SavedAnnotation a, {
  required Rect pageRect,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final topLeft = pdfToCanvas(
    PdfPoint(a.rectPt.left, a.rectPt.top),
    pageRect: pageRect,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  final bottomRight = pdfToCanvas(
    PdfPoint(a.rectPt.right, a.rectPt.bottom),
    pageRect: pageRect,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  return Rect.fromPoints(topLeft, bottomRight);
}

/// Selects saved annotations by tapping them, and outlines the selection.
///
/// Sits above the viewer only in the annotations mode: in read mode it is
/// absent entirely, so it can never intercept a scroll or a pinch.
class AnnotationSelectionOverlay extends ConsumerWidget {
  const AnnotationSelectionOverlay({
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.pageIndex,
    super.key,
  });

  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;
  final int pageIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(annotationEditProvider);
    final controller = ref.read(annotationEditProvider.notifier);
    final onPage = state.session.onPage(pageIndex);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => controller.select(
        annotationAtPoint(
          d.localPosition,
          annotations: onPage,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _SelectionPainter(
          annotations: onPage,
          selected: state.selectedObjectNumber,
          outline: Theme.of(context).colorScheme.primary,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.annotations,
    required this.selected,
    required this.outline,
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final List<SavedAnnotation> annotations;
  final int? selected;
  final Color outline;
  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  void paint(Canvas canvas, Size size) {
    if (selected == null) return;

    for (final a in annotations) {
      if (a.objectNumber != selected) continue;
      final rect = canvasRectOf(
        a,
        pageRect: pageRect,
        pageWidthPt: pageWidthPt,
        pageHeightPt: pageHeightPt,
      ).inflate(3);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = outline
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.selected != selected ||
      old.annotations.length != annotations.length ||
      old.pageRect != pageRect;
}
