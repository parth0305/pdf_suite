import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/features/pages/providers.dart';
import 'package:folio/l10n/app_localizations.dart';

class PageToolbar extends ConsumerWidget {
  const PageToolbar({
    super.key,
    required this.onApply,
    required this.onExtract,
    required this.onInsert,
  });

  final VoidCallback onApply;
  final VoidCallback onExtract;
  final VoidCallback onInsert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(pageSessionProvider);
    final controller = ref.read(pageSessionProvider.notifier);
    final hasSelection = state.selection.isNotEmpty;

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
                      hasSelection
                          ? l10n.pagesSelectedCount(state.selection.length)
                          : '',
                      style: Theme.of(context).textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: hasSelection
                        ? controller.clearSelection
                        : controller.selectAll,
                    child: Text(
                      hasSelection
                          ? l10n.pagesClearSelection
                          : l10n.pagesSelectAll,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Pinned, never inside the scrolling row: the primary action
                  // must not be reachable only by scrolling sideways.
                  FilledButton.icon(
                    onPressed: state.session.isDirty && !state.busy
                        ? onApply
                        : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.pagesApply),
                  ),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l10n.pagesRotateLeft,
                      icon: const Icon(Icons.rotate_left),
                      onPressed: hasSelection
                          ? () => controller.rotateSelected(-1)
                          : null,
                    ),
                    IconButton(
                      tooltip: l10n.pagesRotateRight,
                      icon: const Icon(Icons.rotate_right),
                      onPressed: hasSelection
                          ? () => controller.rotateSelected(1)
                          : null,
                    ),
                    IconButton(
                      tooltip: l10n.pagesDuplicate,
                      icon: const Icon(Icons.content_copy),
                      onPressed: hasSelection
                          ? controller.duplicateSelected
                          : null,
                    ),
                    IconButton(
                      tooltip: l10n.pagesDelete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: hasSelection
                          ? controller.deleteSelected
                          : null,
                    ),
                    IconButton(
                      tooltip: l10n.pagesExtract,
                      icon: const Icon(Icons.call_split),
                      onPressed: hasSelection ? onExtract : null,
                    ),
                    const VerticalDivider(width: 16),
                    IconButton(
                      tooltip: l10n.pagesInsert,
                      icon: const Icon(Icons.library_add_outlined),
                      onPressed: onInsert,
                    ),
                    IconButton(
                      tooltip: l10n.pagesUndo,
                      icon: const Icon(Icons.undo),
                      onPressed: state.session.canUndo ? controller.undo : null,
                    ),
                    IconButton(
                      tooltip: l10n.pagesRedo,
                      icon: const Icon(Icons.redo),
                      onPressed: state.session.canRedo ? controller.redo : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
