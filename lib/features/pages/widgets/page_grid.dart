import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/features/pages/providers.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

/// Selectable, reorderable grid of page thumbnails.
///
/// Uses a builder-based reorderable list so a 1000-page document never holds
/// every thumbnail bitmap at once.
class PageGrid extends ConsumerWidget {
  const PageGrid({super.key, required this.document});

  final PdfDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(pageSessionProvider);
    final controller = ref.read(pageSessionProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: state.session.slots.length,
      onReorder: (from, to) {
        // ReorderableListView reports the destination as if the dragged item
        // were still in place, so shift back when moving downward.
        controller.move(from, to > from ? to - 1 : to);
      },
      itemBuilder: (context, index) {
        final slot = state.session.slots[index];
        final selected = state.selection.contains(index);

        return ReorderableDragStartListener(
          key: ValueKey(
            'page-$index-${slot.sourceDocumentId}-${slot.sourcePageIndex}',
          ),
          index: index,
          child: Semantics(
            label: l10n.viewerPageLabel(index + 1),
            selected: selected,
            button: true,
            child: InkWell(
              onTap: () => controller.toggleSelection(index),
              child: Container(
                height: 190,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                  color: selected ? scheme.primaryContainer : null,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: RotatedBox(
                          quarterTurns: slot.quarterTurns,
                          child: PdfPageView(
                            document: document,
                            pageNumber: slot.sourcePageIndex + 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l10n.viewerPageLabel(index + 1),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (slot.isRotated)
                            Text(
                              '${slot.quarterTurns * 90}°',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.drag_handle, color: scheme.outline),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
