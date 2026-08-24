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

    final subtitle = [
      formatBytes(document.sizeBytes),
      if (document.pageCount != null) l10n.pageCountLabel(document.pageCount!),
      if (document.isManaged) l10n.importedCopyBadge,
    ].join(' · ');

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
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.renameAction)),
              PopupMenuItem(
                value: 'duplicate',
                child: Text(l10n.duplicateAction),
              ),
              PopupMenuItem(value: 'delete', child: Text(l10n.deleteAction)),
            ],
          ),
        ],
      ),
    );
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
