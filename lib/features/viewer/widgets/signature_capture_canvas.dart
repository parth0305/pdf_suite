import 'package:flutter/material.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/stroke_smoothing.dart';
import 'package:folio/domain/signatures/signature_geometry.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Draws a signature and hands back strokes normalised into a unit box, y-up.
///
/// The canvas-to-PDF y flip happens HERE and nowhere else: canvas y grows
/// downward, stored strokes are y-up like PDF user space, and placeSignature
/// assumes that.
class SignatureCaptureCanvas extends StatefulWidget {
  const SignatureCaptureCanvas({required this.onSaved, super.key});

  final void Function(List<List<PdfPoint>> strokes, double aspectRatio) onSaved;

  @override
  State<SignatureCaptureCanvas> createState() => _SignatureCaptureCanvasState();
}

class _SignatureCaptureCanvasState extends State<SignatureCaptureCanvas> {
  final List<List<Offset>> _strokes = [];
  Size _canvasSize = Size.zero;

  bool get _hasSignature => _strokes.any((s) => s.length >= 2);

  void _save() {
    final height = _canvasSize.height;
    final captured = [
      for (final stroke in _strokes)
        if (stroke.length >= 2)
          thinSamples([for (final o in stroke) PdfPoint(o.dx, height - o.dy)]),
    ];
    if (captured.isEmpty) return;

    final normalised = normaliseStrokes(captured);
    widget.onSaved(normalised.strokes, normalised.aspectRatio);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.signDraw, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) =>
                      setState(() => _strokes.add([d.localPosition])),
                  onPanUpdate: (d) =>
                      setState(() => _strokes.last.add(d.localPosition)),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _CapturePainter(
                      strokes: _strokes,
                      ink: scheme.onSurface,
                      baseline: scheme.outlineVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _strokes.isEmpty
                  ? null
                  : () => setState(_strokes.clear),
              child: Text(l10n.signClear),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _hasSignature ? _save : null,
              child: Text(l10n.signSave),
            ),
          ],
        ),
      ],
    );
  }
}

class _CapturePainter extends CustomPainter {
  const _CapturePainter({
    required this.strokes,
    required this.ink,
    required this.baseline,
  });

  final List<List<Offset>> strokes;
  final Color ink;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(16, size.height * 0.75),
      Offset(size.width - 16, size.height * 0.75),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    final paint = Paint()
      ..color = ink
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CapturePainter old) => true;
}

/// Paints a saved signature's strokes to fill [size]. Used for previews, so a
/// signature never needs a thumbnail file kept in sync with its data.
class SignaturePreviewPainter extends CustomPainter {
  const SignaturePreviewPainter({required this.strokes, required this.ink});

  /// Normalised, y-up.
  final List<List<PdfPoint>> strokes;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      Offset at(PdfPoint p) =>
          Offset(p.x * size.width, (1 - p.y) * size.height);

      final path = Path()..moveTo(at(stroke.first).dx, at(stroke.first).dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SignaturePreviewPainter old) => old.strokes != strokes;
}
