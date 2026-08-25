import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Horizontal folder chips. Folders are virtual, so selecting one filters the
/// list rather than navigating anywhere.
class CollectionBar extends ConsumerWidget {
  const CollectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final collections = ref.watch(collectionsControllerProvider);
    final selected = ref.watch(selectedCollectionProvider);
    final controller = ref.read(collectionsControllerProvider.notifier);

    return collections.when(
      loading: () => const SizedBox(height: 48),
      error: (_, _) => const SizedBox(height: 48),
      data: (folders) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(l10n.collectionsAll),
                selected: selected == null,
                onSelected: (_) =>
                    ref.read(selectedCollectionProvider.notifier).value = null,
              ),
            ),
            for (final folder in folders)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onLongPress: () =>
                      _folderMenu(context, ref, folder.id, folder.name),
                  child: ChoiceChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(folder.name),
                    selected: selected == folder.id,
                    onSelected: (_) =>
                        ref.read(selectedCollectionProvider.notifier).value =
                            folder.id,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: Text(l10n.collectionNew),
                onPressed: () async {
                  final name = await _promptName(
                    context,
                    l10n.collectionNew,
                    '',
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    await controller.create(name.trim());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _folderMenu(
    BuildContext context,
    WidgetRef ref,
    int id,
    String name,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(collectionsControllerProvider.notifier);

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(l10n.renameFolderAction),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_delete_outlined),
              title: Text(l10n.deleteFolderAction),
              subtitle: Text(l10n.deleteFolderExplain),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;

    switch (action) {
      case 'rename':
        final next = await _promptName(context, l10n.renameFolderAction, name);
        if (next != null && next.trim().isNotEmpty) {
          await controller.rename(id, next.trim());
        }
      case 'delete':
        await controller.remove(id);
    }
  }

  Future<String?> _promptName(
    BuildContext context,
    String title,
    String initial,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.collectionNameHint),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: Text(l10n.createAction),
          ),
        ],
      ),
    );
  }
}
