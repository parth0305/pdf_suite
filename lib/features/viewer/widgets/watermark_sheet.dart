import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'package:folio/features/viewer/widgets/drawing_toolbar.dart'
    show drawingColours;
import 'package:folio/l10n/app_localizations.dart';

/// Collects a watermark, previewing it as it will be drawn.
///
/// Returns the watermark to apply, or null if cancelled.
Future<Watermark?> showWatermarkSheet(BuildContext context) =>
    showModalBottomSheet<Watermark>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _WatermarkSheet(),
    );

class _WatermarkSheet extends StatefulWidget {
  const _WatermarkSheet();

  @override
  State<_WatermarkSheet> createState() => _WatermarkSheetState();
}

class _WatermarkSheetState extends State<_WatermarkSheet> {
  Watermark _mark = const Watermark(text: 'DRAFT');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final blank = _mark.text.trim().isEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.watermarkMode,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              // The preview draws the same text, rotation and opacity the
              // content stream will, so what is shown is what gets written.
              AspectRatio(
                aspectRatio: 595 / 842,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: CustomPaint(painter: _WatermarkPreviewPainter(_mark)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _mark.text,
                decoration: InputDecoration(
                  labelText: l10n.watermarkText,
                  hintText: l10n.watermarkHint,
                  helperText: blank ? l10n.watermarkEmpty : null,
                ),
                onChanged: (v) =>
                    setState(() => _mark = _mark.copyWith(text: v)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(l10n.watermarkSize),
                  Expanded(
                    child: Slider(
                      value: _mark.fontSizePt,
                      min: 12,
                      max: 144,
                      onChanged: (v) =>
                          setState(() => _mark = _mark.copyWith(fontSizePt: v)),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(l10n.watermarkOpacity),
                  Expanded(
                    child: Slider(
                      value: _mark.opacity,
                      min: 0.05,
                      max: 1,
                      onChanged: (v) =>
                          setState(() => _mark = _mark.copyWith(opacity: v)),
                    ),
                  ),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final argb in drawingColours)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () => setState(
                            () => _mark = _mark.copyWith(colorArgb: argb),
                          ),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Color(argb),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _mark.colorArgb == argb
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<WatermarkRotation>(
                segments: [
                  ButtonSegment(
                    value: WatermarkRotation.diagonal,
                    label: Text(l10n.watermarkDiagonal),
                  ),
                  ButtonSegment(
                    value: WatermarkRotation.horizontal,
                    label: Text(l10n.watermarkHorizontal),
                  ),
                ],
                selected: {_mark.rotation},
                onSelectionChanged: (s) =>
                    setState(() => _mark = _mark.copyWith(rotation: s.first)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: blank
                    ? null
                    : () => Navigator.of(context).pop(_mark),
                icon: const Icon(Icons.branding_watermark_outlined),
                label: Text(l10n.watermarkApply),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatermarkPreviewPainter extends CustomPainter {
  const _WatermarkPreviewPainter(this.mark);

  final Watermark mark;

  @override
  void paint(Canvas canvas, Size size) {
    if (mark.text.trim().isEmpty) return;

    // The preview page stands in for A4, so scale the point size to match.
    final scale = size.width / 595;
    final painter = TextPainter(
      text: TextSpan(
        text: mark.text,
        style: TextStyle(
          color: Color(mark.colorArgb).withValues(alpha: mark.opacity),
          fontSize: mark.fontSizePt * scale,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2);
    if (mark.rotation == WatermarkRotation.diagonal) {
      canvas.rotate(-55 * math.pi / 180);
    }
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatermarkPreviewPainter old) => old.mark != mark;
}
