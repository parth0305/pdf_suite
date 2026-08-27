import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/redaction/redaction_box.dart';
import 'package:folio/features/viewer/redaction_providers.dart';

/// Drag a rectangle over anything that should be removed.
///
/// Present only in redact mode, so it cannot compete with the viewer for
/// scroll or pinch. Tapping an existing box removes it, which is the whole of
/// "undo" here: a box that has not been applied costs nothing to redraw.
class RedactOverlay extends ConsumerStatefulWidget {
  const RedactOverlay({
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
  ConsumerState<RedactOverlay> createState() => _RedactOverlayState();
}

class _RedactOverlayState extends ConsumerState<RedactOverlay> {
  Offset? _start;
  Offset? _current;

  TextRect _pdfRectOf(Offset a, Offset b) {
    final p1 = canvasToPdf(
      a,
      pageRect: widget.pageRect,
      pageWidthPt: widget.pageWidthPt,
      pageHeightPt: widget.pageHeightPt,
    );
    final p2 = canvasToPdf(
      b,
      pageRect: widget.pageRect,
      pageWidthPt: widget.pageWidthPt,
      pageHeightPt: widget.pageHeightPt,
    );

    return TextRect(
      left: p1.x < p2.x ? p1.x : p2.x,
      right: p1.x > p2.x ? p1.x : p2.x,
      top: p1.y > p2.y ? p1.y : p2.y,
      bottom: p1.y < p2.y ? p1.y : p2.y,
    );
  }

  @override
  Widget build(BuildContext context) {
    final boxes = ref
        .watch(redactionSessionProvider)
        .where((b) => b.pageIndex == widget.pageIndex)
        .toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => setState(() {
        _start = d.localPosition;
        _current = d.localPosition;
      }),
      onPanUpdate: (d) => setState(() => _current = d.localPosition),
      onPanEnd: (_) {
        final start = _start;
        final current = _current;
        setState(() {
          _start = null;
          _current = null;
        });
        if (start == null || current == null) return;

        // A stray tap is not a redaction. Anything under a few points across
        // is almost certainly an accident, and an invisible box the user
        // cannot see to remove is worse than no box.
        final rect = _pdfRectOf(start, current);
        if (rect.width < 2 || rect.height < 2) return;

        ref
            .read(redactionSessionProvider.notifier)
            .add(RedactionBox(pageIndex: widget.pageIndex, rect: rect));
      },
      onTapUp: (d) {
        for (var i = boxes.length - 1; i >= 0; i--) {
          if (_canvasRectOf(boxes[i].rect).contains(d.localPosition)) {
            final all = ref.read(redactionSessionProvider);
            ref
                .read(redactionSessionProvider.notifier)
                .removeAt(all.indexOf(boxes[i]));
            return;
          }
        }
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _BoxPainter(
          rects: [
            for (final b in boxes) _canvasRectOf(b.rect),
            if (_start != null && _current != null)
              Rect.fromPoints(_start!, _current!),
          ],
        ),
      ),
    );
  }

  Rect _canvasRectOf(TextRect r) {
    final topLeft = pdfToCanvas(
      PdfPoint(r.left, r.top),
      pageRect: widget.pageRect,
      pageWidthPt: widget.pageWidthPt,
      pageHeightPt: widget.pageHeightPt,
    );
    final bottomRight = pdfToCanvas(
      PdfPoint(r.right, r.bottom),
      pageRect: widget.pageRect,
      pageWidthPt: widget.pageWidthPt,
      pageHeightPt: widget.pageHeightPt,
    );

    return Rect.fromPoints(topLeft, bottomRight);
  }
}

/// Draws pending boxes solid, with a border so a box over dark content is
/// still visible as a box.
class _BoxPainter extends CustomPainter {
  const _BoxPainter({required this.rects});

  final List<Rect> rects;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFF000000);
    final border = Paint()
      ..color = const Color(0xFFFF5252)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final r in rects) {
      canvas
        ..drawRect(r, fill)
        ..drawRect(r, border);
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.rects != rects;
}
