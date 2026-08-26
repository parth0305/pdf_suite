import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/signatures/signature_geometry.dart';
import 'package:folio/features/viewer/annotation_providers.dart';
import 'package:folio/features/viewer/signature_providers.dart';

/// Drag a box; the chosen signature is fitted into it.
///
/// Present only in signature mode, so it cannot compete with the viewer for
/// scroll or pinch. The preview and the placed annotation both come from
/// placeSignature, so what the user sees is what gets written.
class SignaturePlacementSurface extends ConsumerStatefulWidget {
  const SignaturePlacementSurface({
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
  ConsumerState<SignaturePlacementSurface> createState() =>
      _SignaturePlacementSurfaceState();
}

class _SignaturePlacementSurfaceState
    extends ConsumerState<SignaturePlacementSurface> {
  Offset? _start;
  Offset? _current;

  PdfPoint _toPdf(Offset o) => canvasToPdf(
    o,
    pageRect: widget.pageRect,
    pageWidthPt: widget.pageWidthPt,
    pageHeightPt: widget.pageHeightPt,
  );

  TextRect? _boxPt() {
    final start = _start;
    final current = _current;
    if (start == null || current == null) return null;

    final a = _toPdf(start);
    final b = _toPdf(current);
    // Normalised, so dragging up-left works exactly like down-right.
    return TextRect(
      left: a.x < b.x ? a.x : b.x,
      right: a.x > b.x ? a.x : b.x,
      bottom: a.y < b.y ? a.y : b.y,
      top: a.y > b.y ? a.y : b.y,
    );
  }

  void _commit() {
    final box = _boxPt();
    final chosen = ref.read(signingProvider).chosen;

    setState(() {
      _start = null;
      _current = null;
    });

    if (box == null || chosen == null) return;
    // A stray tap must not drop a signature nobody can see.
    if (box.right - box.left < 20 || box.top - box.bottom < 20) return;

    ref
        .read(annotationSessionProvider.notifier)
        .addSignature(signature: chosen, pageIndex: widget.pageIndex, box: box);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = ref.watch(signingProvider).chosen;
    final staged = ref
        .watch(annotationSessionProvider)
        .session
        .annotationsOnPage(widget.pageIndex);

    final previewBox = _boxPt();
    final preview = (previewBox == null || chosen == null)
        ? const <List<PdfPoint>>[]
        : placeSignature(chosen, box: previewBox);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => setState(() {
        _start = d.localPosition;
        _current = d.localPosition;
      }),
      onPanUpdate: (d) => setState(() => _current = d.localPosition),
      onPanEnd: (_) => _commit(),
      child: CustomPaint(
        size: Size.infinite,
        painter: _PlacementPainter(
          dragStart: _start,
          dragCurrent: _current,
          preview: preview,
          stagedCount: staged.length,
          outline: Theme.of(context).colorScheme.primary,
          pageRect: widget.pageRect,
          pageWidthPt: widget.pageWidthPt,
          pageHeightPt: widget.pageHeightPt,
        ),
      ),
    );
  }
}

class _PlacementPainter extends CustomPainter {
  const _PlacementPainter({
    required this.dragStart,
    required this.dragCurrent,
    required this.preview,
    required this.stagedCount,
    required this.outline,
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
  });

  final Offset? dragStart;
  final Offset? dragCurrent;
  final List<List<PdfPoint>> preview;
  final int stagedCount;
  final Color outline;
  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  void paint(Canvas canvas, Size size) {
    if (dragStart != null && dragCurrent != null) {
      canvas.drawRect(
        Rect.fromPoints(dragStart!, dragCurrent!),
        Paint()
          ..color = outline.withValues(alpha: 0.6)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset at(PdfPoint p) => pdfToCanvas(
      p,
      pageRect: pageRect,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
    );

    for (final stroke in preview) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(at(stroke.first).dx, at(stroke.first).dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_PlacementPainter old) =>
      old.dragCurrent != dragCurrent ||
      old.dragStart != dragStart ||
      old.stagedCount != stagedCount ||
      old.pageRect != pageRect;
}
