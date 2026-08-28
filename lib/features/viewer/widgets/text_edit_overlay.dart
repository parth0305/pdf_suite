import 'package:flutter/material.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/editing/pdf_text_editor.dart';

/// Shows which words on the page can be changed, and lets one be tapped.
///
/// Runs that cannot be edited are drawn too, in a quieter style. Hiding them
/// would leave someone tapping at a word and getting nothing, with no way to
/// tell whether they had missed it or it was fixed.
class TextEditOverlay extends StatelessWidget {
  const TextEditOverlay({
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.runs,
    required this.onTap,
    super.key,
  });

  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;

  /// The runs on THIS page, already filtered by the caller.
  final List<EditableRun> runs;

  final ValueChanged<EditableRun> onTap;

  /// Where a run sits on screen.
  ///
  /// A run knows its baseline, not its box: the height comes from the font
  /// size, and the width from how far the glyphs advance. Both are estimates
  /// for the purpose of being tapped, which is all this rectangle is for.
  Rect _rectFor(EditableRun run) {
    final size = run.run.transform.verticalScale;
    final width = run.font == null
        ? size * run.run.bytes.length * 0.5
        : _advanceOf(run);

    final origin = pdfToCanvas(
      PdfPoint(run.x, run.y + size * 0.8),
      pageRect: pageRect,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
    );
    final far = pdfToCanvas(
      PdfPoint(run.x + width, run.y - size * 0.25),
      pageRect: pageRect,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
    );

    return Rect.fromLTRB(origin.dx, origin.dy, far.dx, far.dy);
  }

  double _advanceOf(EditableRun run) {
    final text = run.text;
    if (text == null) return run.run.transform.verticalScale * 4;

    var total = 0.0;
    for (final code in run.run.bytes) {
      total += run.font!.widthOf(code) ?? 500;
    }

    return total / 1000 * run.run.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        for (final run in runs)
          Positioned.fromRect(
            rect: _rectFor(run),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: run.isEditable ? () => onTap(run) : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: run.isEditable
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.25,
                        ),
                  border: Border.all(
                    color: run.isEditable
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: run.isEditable ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
