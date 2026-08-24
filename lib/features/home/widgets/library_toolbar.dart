import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/services/document_sorter.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/l10n/app_localizations.dart';

class LibraryToolbar extends ConsumerStatefulWidget {
  const LibraryToolbar({super.key});

  @override
  ConsumerState<LibraryToolbar> createState() => _LibraryToolbarState();
}

class _LibraryToolbarState extends ConsumerState<LibraryToolbar> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ascending = ref.watch(sortAscendingProvider);
    final isRecents = ref.watch(selectedTabProvider) == LibraryTab.recents;

    String labelFor(SortField f) => switch (f) {
      SortField.name => l10n.sortByName,
      SortField.dateAdded => l10n.sortByDateAdded,
      SortField.dateOpened => l10n.sortByDateOpened,
      SortField.size => l10n.sortBySize,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _field,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _field.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _field.clear();
                          ref.read(searchQueryProvider.notifier).value = '';
                          setState(() {});
                        },
                      ),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                ref.read(searchQueryProvider.notifier).value = v;
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          // Recents is inherently ordered by last-opened, so sort controls
          // would be misleading there.
          if (!isRecents) ...[
            PopupMenuButton<SortField>(
              icon: const Icon(Icons.sort),
              tooltip: l10n.sortLabel,
              onSelected: (f) => ref.read(sortFieldProvider.notifier).value = f,
              itemBuilder: (context) => [
                for (final f in SortField.values)
                  if (f != SortField.dateOpened)
                    PopupMenuItem(value: f, child: Text(labelFor(f))),
              ],
            ),
            IconButton(
              tooltip: ascending ? l10n.sortAscending : l10n.sortDescending,
              icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward),
              onPressed: () =>
                  ref.read(sortAscendingProvider.notifier).value = !ascending,
            ),
          ],
        ],
      ),
    );
  }
}
