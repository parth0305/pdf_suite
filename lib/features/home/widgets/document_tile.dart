import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/l10n/app_localizations.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class DocumentTile extends ConsumerWidget {
  const DocumentTile({super.key, required this.document, this.onOpen});

  final LibraryDocument document;
  final ValueChanged<LibraryDocument>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(libraryControllerProvider.notifier);
    final selectMode = ref.watch(librarySelectModeProvider);
    final selected = ref.watch(librarySelectionProvider).contains(document.id);

    final subtitle = [
      formatBytes(document.sizeBytes),
      if (document.pageCount != null) l10n.pageCountLabel(document.pageCount!),
      if (document.isManaged) l10n.importedCopyBadge,
    ].join(' · ');

    if (selectMode) {
      return ListTile(
        leading: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          document.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: selected,
        onTap: () {
          final next = Set<int>.of(ref.read(librarySelectionProvider));
          if (!next.remove(document.id)) next.add(document.id);
          ref.read(librarySelectionProvider.notifier).value = next;
        },
      );
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          Icons.description_outlined,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(
        document.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onOpen == null ? null : () => onOpen!(document),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(document.isFavorite ? Icons.star : Icons.star_border),
            tooltip: document.isFavorite
                ? l10n.unfavoriteAction
                : l10n.favoriteAction,
            onPressed: () => controller.toggleFavorite(document.id),
          ),
          PopupMenuButton<String>(
            // Explicit icon: PopupMenuButton defaults to more_horiz on iOS and
            // more_vert on Android, which makes the control inconsistent and
            // platform-dependent to find.
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.moreActionsLabel,
            onSelected: (action) async {
              switch (action) {
                case 'rename':
                  final name = await _promptRename(
                    context,
                    document.displayName,
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    await controller.renameDocument(document.id, name.trim());
                  }
                case 'duplicate':
                  await controller.duplicateDocument(document.id);
                case 'delete':
                  await controller.remove(document.id);
                case 'saveAs':
                  final location = await getSaveLocation(
                    suggestedName: document.displayName,
                  );
                  if (location == null) return;
                  await controller.exportCopy(document.id, location.path);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.exportSuccess)));
                case 'move':
                  if (!context.mounted) return;
                  await _promptMove(context, ref, document.id);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.renameAction)),
              PopupMenuItem(
                value: 'duplicate',
                child: Text(l10n.duplicateAction),
              ),
              PopupMenuItem(value: 'move', child: Text(l10n.moveToAction)),
              PopupMenuItem(value: 'saveAs', child: Text(l10n.saveAsAction)),
              PopupMenuItem(value: 'delete', child: Text(l10n.deleteAction)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _promptMove(
    BuildContext context,
    WidgetRef ref,
    int docId,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final folders = ref.read(collectionsControllerProvider).value ?? const [];

    final target = await showModalBottomSheet<int?>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(l10n.moveToRoot),
              onTap: () => Navigator.of(context).pop(-1),
            ),
            for (final f in folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.name),
                onTap: () => Navigator.of(context).pop(f.id),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;

    // -1 is the sentinel for "library root"; null would be indistinguishable
    // from the user dismissing the sheet.
    await ref
        .read(libraryControllerProvider.notifier)
        .moveToCollection(docId, target == -1 ? null : target);
  }

  Future<String?> _promptRename(BuildContext context, String current) {
    final l10n = AppLocalizations.of(context)!;
    final field = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameAction),
        content: TextField(
          controller: field,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    );
  }
}
