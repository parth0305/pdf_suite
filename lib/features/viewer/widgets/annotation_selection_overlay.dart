import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation_edit_session.dart';
import 'package:folio/domain/annotations/annotation_transform.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
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
  TextRect? override,
}) {
  final r = override ?? a.rectPt;
  final topLeft = pdfToCanvas(
    PdfPoint(r.left, r.top),
    pageRect: pageRect,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  final bottomRight = pdfToCanvas(
    PdfPoint(r.right, r.bottom),
    pageRect: pageRect,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  return Rect.fromPoints(topLeft, bottomRight);
}

/// Selects saved annotations by tapping them, and moves or resizes them by
/// dragging.
///
/// Sits above the viewer only in the annotations mode: in read mode it is
/// absent entirely, so it can never intercept a scroll or a pinch.
class AnnotationSelectionOverlay extends ConsumerStatefulWidget {
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
  ConsumerState<AnnotationSelectionOverlay> createState() =>
      _AnnotationSelectionOverlayState();
}

/// How close a touch must be to a corner to count as grabbing its handle.
const _handleGrabRadius = 24.0;

class _AnnotationSelectionOverlayState
    extends ConsumerState<AnnotationSelectionOverlay> {
  Rect? _liveRect;
  int? _activeCorner;
  Offset? _dragOrigin;
  Rect? _dragStartRect;

  /// Where the annotation is NOW, staged move included - not where it started.
  /// Reading rectPt would snap the outline back on every second drag.
  TextRect effectiveRect(SavedAnnotation a, AnnotationEditSession session) =>
      session.moved[a.objectNumber] ?? a.rectPt;

  Rect _canvasRect(SavedAnnotation a, AnnotationEditSession session) =>
      canvasRectOf(
        a,
        pageRect: widget.pageRect,
        pageWidthPt: widget.pageWidthPt,
        pageHeightPt: widget.pageHeightPt,
        override: effectiveRect(a, session),
      );

  List<Offset> _cornersOf(Rect r) => [
    r.topLeft,
    r.topRight,
    r.bottomLeft,
    r.bottomRight,
  ];

  void _commit(SavedAnnotation target) {
    final live = _liveRect;
    setState(() {
      _liveRect = null;
      _activeCorner = null;
      _dragOrigin = null;
      _dragStartRect = null;
    });
    if (live == null) return;

    PdfPoint toPdf(Offset o) => canvasToPdf(
      o,
      pageRect: widget.pageRect,
      pageWidthPt: widget.pageWidthPt,
      pageHeightPt: widget.pageHeightPt,
    );

    final a = toPdf(live.topLeft);
    final b = toPdf(live.bottomRight);
    final rect = TextRect(
      left: a.x < b.x ? a.x : b.x,
      right: a.x > b.x ? a.x : b.x,
      bottom: a.y < b.y ? a.y : b.y,
      top: a.y > b.y ? a.y : b.y,
    );

    // An annotation dragged down to nothing cannot be selected again to undo
    // it, so refuse rather than let the user lose it.
    if (rect.right - rect.left < 8 || rect.top - rect.bottom < 8) return;

    ref.read(annotationEditProvider.notifier).moveSelected(rect);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(annotationEditProvider);
    final controller = ref.read(annotationEditProvider.notifier);
    final onPage = state.session.onPage(widget.pageIndex);

    final selected = state.selectedObjectNumber == null
        ? null
        : onPage
              .where((a) => a.objectNumber == state.selectedObjectNumber)
              .firstOrNull;
    final selectedRect = selected == null
        ? null
        : _canvasRect(selected, state.session);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => controller.select(
        annotationAtPoint(
          d.localPosition,
          annotations: onPage,
          pageRect: widget.pageRect,
          pageWidthPt: widget.pageWidthPt,
          pageHeightPt: widget.pageHeightPt,
        ),
      ),
      onPanStart: (d) {
        if (selected == null || selectedRect == null) return;

        final corners = _cornersOf(selectedRect);
        for (var i = 0; i < corners.length; i++) {
          if (selected.resizable &&
              (corners[i] - d.localPosition).distance <= _handleGrabRadius) {
            setState(() {
              _activeCorner = i;
              _liveRect = selectedRect;
            });
            return;
          }
        }

        if (selected.movable && selectedRect.contains(d.localPosition)) {
          setState(() {
            _activeCorner = null;
            _dragOrigin = d.localPosition;
            _dragStartRect = selectedRect;
            _liveRect = selectedRect;
          });
        }
      },
      onPanUpdate: (d) {
        if (selected == null || _liveRect == null) return;

        setState(() {
          final corner = _activeCorner;
          if (corner == null) {
            final origin = _dragOrigin!;
            final startRect = _dragStartRect!;
            _liveRect = startRect.shift(d.localPosition - origin);
            return;
          }

          final r = _liveRect!;
          final fixed = _cornersOf(r)[3 - corner];
          var next = Rect.fromPoints(fixed, d.localPosition);

          // Stretched handwriting and a squashed APPROVED both read as broken.
          if (selected.subtype == 'Ink' || selected.subtype == 'Stamp') {
            final locked = lockAspect(
              TextRect(
                left: next.left,
                top: next.top,
                right: next.right,
                bottom: next.bottom,
              ),
              original: TextRect(
                left: r.left,
                top: r.top,
                right: r.right,
                bottom: r.bottom,
              ),
            );
            next = Rect.fromLTRB(
              locked.left,
              locked.top,
              locked.right,
              locked.bottom,
            );
          }
          _liveRect = next;
        });
      },
      onPanEnd: (_) {
        if (selected == null) return;
        _commit(selected);
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _SelectionPainter(
          outlineRect: _liveRect ?? selectedRect,
          showHandles: selected?.resizable ?? false,
          outline: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.outlineRect,
    required this.showHandles,
    required this.outline,
  });

  final Rect? outlineRect;
  final bool showHandles;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = outlineRect;
    if (rect == null) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(3)),
      Paint()
        ..color = outline
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Handles only where a resize is possible, which keeps them off a 20pt
    // note icon they would completely cover.
    if (!showHandles) return;
    final fill = Paint()..color = outline;
    for (final c in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(c, 6, fill);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.outlineRect != outlineRect || old.showHandles != showHandles;
}
