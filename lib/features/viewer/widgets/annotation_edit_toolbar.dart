import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/features/viewer/annotation_edit_providers.dart';
import 'package:folio/features/viewer/widgets/note_dialog.dart';
import 'package:folio/features/viewer/widgets/annotation_list_panel.dart';
import 'package:folio/features/viewer/widgets/drawing_toolbar.dart'
    show drawingColours;
import 'package:folio/l10n/app_localizations.dart';

class AnnotationEditToolbar extends ConsumerWidget {
  const AnnotationEditToolbar({
    required this.onSave,
    required this.pageIndex,
    super.key,
  });

  final VoidCallback onSave;
  final int pageIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(annotationEditProvider);
    final controller = ref.read(annotationEditProvider.notifier);

    final selectedNumber = state.selectedObjectNumber;
    final selected = selectedNumber == null
        ? null
        : state.session.annotations
              .where((a) => a.objectNumber == selectedNumber)
              .firstOrNull;

    final canRestyle = selected?.restylable ?? false;
    // A /Text icon has no stroke, so a thickness control would do nothing.
    final isNote = selected?.subtype == 'Text';
    final staged = selectedNumber == null
        ? null
        : state.session.styleOf(selectedNumber);
    final colour = staged?.colorArgb ?? selected?.colorArgb ?? 0xFF000000;
    final width = staged?.strokeWidth ?? selected?.strokeWidth ?? 2;

    void apply({int? newColour, double? newWidth}) {
      controller.restyleSelected(
        AnnotationStyle(
          colorArgb: newColour ?? colour,
          strokeWidth: newWidth ?? width,
        ),
      );
    }

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
                      selected == null
                          ? l10n.annotationsSelectFirst
                          : (canRestyle
                                ? selected.subtype
                                : '${selected.subtype} · '
                                      '${l10n.annotationsDeleteOnly}'),
                      style: Theme.of(context).textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Tapping is not enough on its own: annotations overlap and
                  // a thin stroke is hard to hit. The list reaches all of them.
                  IconButton(
                    tooltip: l10n.annotationsMode,
                    icon: const Icon(Icons.list),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => SizedBox(
                        height: 320,
                        child: AnnotationListPanel(pageIndex: pageIndex),
                      ),
                    ),
                  ),
                  if (isNote)
                    IconButton(
                      tooltip: l10n.noteText,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final note = selected!.reconstructed! as StickyNote;
                        final text = await showNoteDialog(
                          context,
                          initial: staged?.contents ?? note.contents,
                        );
                        if (text == null) return;
                        controller.restyleSelected(
                          AnnotationStyle(
                            colorArgb: colour,
                            strokeWidth: width,
                            contents: text,
                          ),
                        );
                      },
                    ),
                  IconButton(
                    tooltip: l10n.annotationsUndo,
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
                    label: Text(l10n.annotationsSave),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final argb in drawingColours)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Opacity(
                          opacity: canRestyle ? 1 : 0.35,
                          child: InkWell(
                            onTap: canRestyle
                                ? () => apply(newColour: argb)
                                : null,
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Color(argb),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colour == argb
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: selected == null
                          ? null
                          : controller.deleteSelected,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.annotationsDelete),
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
                      value: width.clamp(1, 8),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: width.round().toString(),
                      onChanged: canRestyle ? (v) => apply(newWidth: v) : null,
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
