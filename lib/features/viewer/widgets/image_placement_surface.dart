import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

/// Drag a box; the chosen image is fitted into it.
///
/// The same shape as signature placement, and for the same reason: an image
/// dropped at a tap would need a size from somewhere, and guessing one is how
/// a picture ends up the wrong size on every page.
class ImagePlacementSurface extends ConsumerStatefulWidget {
  const ImagePlacementSurface({
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.pageIndex,
    required this.rgba,
    required this.pixelWidth,
    required this.pixelHeight,
    super.key,
  });

  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;
  final int pageIndex;
  final List<int> rgba;
  final int pixelWidth;
  final int pixelHeight;

  @override
  ConsumerState<ImagePlacementSurface> createState() =>
      _ImagePlacementSurfaceState();
}

class _ImagePlacementSurfaceState extends ConsumerState<ImagePlacementSurface> {
  Offset? _start;
  Offset? _current;

  @override
  Widget build(BuildContext context) {
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

        final a = canvasToPdf(
          start,
          pageRect: widget.pageRect,
          pageWidthPt: widget.pageWidthPt,
          pageHeightPt: widget.pageHeightPt,
        );
        final b = canvasToPdf(
          current,
          pageRect: widget.pageRect,
          pageWidthPt: widget.pageWidthPt,
          pageHeightPt: widget.pageHeightPt,
        );

        final box = TextRect(
          left: a.x < b.x ? a.x : b.x,
          right: a.x > b.x ? a.x : b.x,
          top: a.y > b.y ? a.y : b.y,
          bottom: a.y < b.y ? a.y : b.y,
        );

        // A stray tap must not drop an invisible image on the page.
        if (box.width < 8 || box.height < 8) return;

        ref
            .read(annotationSessionProvider.notifier)
            .addImage(
              pageIndex: widget.pageIndex,
              box: box,
              rgba: widget.rgba,
              pixelWidth: widget.pixelWidth,
              pixelHeight: widget.pixelHeight,
            );
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _BoxPainter(
          rect: _start != null && _current != null
              ? Rect.fromPoints(_start!, _current!)
              : null,
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  const _BoxPainter({this.rect});

  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect;
    if (r == null) return;

    canvas.drawRect(
      r,
      Paint()
        ..color = const Color(0xFF2F5D62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.rect != rect;
}
