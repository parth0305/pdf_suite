import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/features/viewer/annotation_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

class MarkupToolbar extends ConsumerWidget {
  const MarkupToolbar({
    super.key,
    required this.hasSelection,
    required this.onMarkup,
    required this.onSave,
  });

  final bool hasSelection;
  final ValueChanged<MarkupKind> onMarkup;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(annotationSessionProvider);
    final controller = ref.read(annotationSessionProvider.notifier);
    final count = state.session.markups.length;

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
                      count == 0
                          ? (hasSelection ? '' : l10n.markupSelectFirst)
                          : l10n.markupCount(count),
                      style: Theme.of(context).textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Pinned, never inside the scrolling row: the primary action
                  // must not be reachable only by scrolling sideways.
                  FilledButton.icon(
                    onPressed: state.session.isDirty && !state.busy
                        ? onSave
                        : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.markupSave),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.markupHighlight,
                    icon: const Icon(Icons.format_color_fill),
                    onPressed: hasSelection
                        ? () => onMarkup(MarkupKind.highlight)
                        : null,
                  ),
                  IconButton(
                    tooltip: l10n.markupUnderline,
                    icon: const Icon(Icons.format_underlined),
                    onPressed: hasSelection
                        ? () => onMarkup(MarkupKind.underline)
                        : null,
                  ),
                  IconButton(
                    tooltip: l10n.markupStrikeOut,
                    icon: const Icon(Icons.format_strikethrough),
                    onPressed: hasSelection
                        ? () => onMarkup(MarkupKind.strikeOut)
                        : null,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.markupUndo,
                    icon: const Icon(Icons.undo),
                    onPressed: state.session.canUndo ? controller.undo : null,
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
