import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/features/viewer/annotation_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// The palette offered while drawing. Deliberately small: a full colour picker
/// buys little on a document and costs a screen of chrome.
const drawingColours = <int>[
  0xFF000000,
  0xFFD32F2F,
  0xFF1976D2,
  0xFF388E3C,
  0xFFF9A825,
];

class DrawingToolbar extends ConsumerWidget {
  const DrawingToolbar({
    required this.tool,
    required this.colorArgb,
    required this.strokeWidth,
    required this.onToolChanged,
    required this.onColourChanged,
    required this.onStrokeWidthChanged,
    required this.onSave,
    super.key,
  });

  final DrawingKind tool;
  final int colorArgb;
  final double strokeWidth;
  final ValueChanged<DrawingKind> onToolChanged;
  final ValueChanged<int> onColourChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(annotationSessionProvider);
    final controller = ref.read(annotationSessionProvider.notifier);

    final labels = <DrawingKind, String>{
      DrawingKind.ink: l10n.drawPen,
      DrawingKind.rectangle: l10n.drawRectangle,
      DrawingKind.ellipse: l10n.drawOval,
      DrawingKind.line: l10n.drawLine,
      DrawingKind.arrow: l10n.drawArrow,
    };
    final icons = <DrawingKind, IconData>{
      DrawingKind.ink: Icons.draw_outlined,
      DrawingKind.rectangle: Icons.crop_square,
      DrawingKind.ellipse: Icons.circle_outlined,
      DrawingKind.line: Icons.horizontal_rule,
      DrawingKind.arrow: Icons.arrow_forward,
    };

    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      state.session.isEmpty
                          ? labels[tool]!
                          : l10n.markupCount(state.session.annotations.length),
                      style: Theme.of(context).textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: l10n.drawUndo,
                    icon: const Icon(Icons.undo),
                    onPressed: state.session.canUndo ? controller.undo : null,
                  ),
                  // Pinned, never inside the scrolling row: the primary action
                  // must not be reachable only by scrolling sideways.
                  FilledButton.icon(
                    onPressed: state.session.isDirty && !state.busy
                        ? onSave
                        : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.drawSave),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final kind in DrawingKind.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: IconButton(
                          tooltip: labels[kind],
                          icon: Icon(icons[kind]),
                          isSelected: tool == kind,
                          style: IconButton.styleFrom(
                            backgroundColor: tool == kind
                                ? Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer
                                : null,
                          ),
                          onPressed: () => onToolChanged(kind),
                        ),
                      ),
                    const SizedBox(width: 8),
                    for (final argb in drawingColours)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Semantics(
                          label: l10n.drawColour,
                          selected: colorArgb == argb,
                          child: InkWell(
                            onTap: () => onColourChanged(argb),
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Color(argb),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorArgb == argb
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    l10n.drawThickness,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Expanded(
                    child: Slider(
                      value: strokeWidth,
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: strokeWidth.round().toString(),
                      onChanged: onStrokeWidthChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
