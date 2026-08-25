import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/errors/failure_messages.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/home/widgets/collection_bar.dart';
import 'package:folio/features/home/widgets/document_tile.dart';
import 'package:folio/features/home/widgets/empty_state.dart';
import 'package:folio/features/home/widgets/library_toolbar.dart';
import 'package:folio/l10n/app_localizations.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.onOpenDocument});

  final ValueChanged<LibraryDocument>? onOpenDocument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tab = ref.watch(selectedTabProvider);
    final visible = ref.watch(visibleDocumentsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(144),
          child: Column(
            children: [
              const CollectionBar(),
              SegmentedButton<LibraryTab>(
                segments: [
                  ButtonSegment(
                    value: LibraryTab.all,
                    label: Text(l10n.allDocumentsTitle),
                    icon: const Icon(Icons.folder_outlined),
                  ),
                  ButtonSegment(
                    value: LibraryTab.recents,
                    label: Text(l10n.recentsTitle),
                    icon: const Icon(Icons.history),
                  ),
                  ButtonSegment(
                    value: LibraryTab.favorites,
                    label: Text(l10n.favoritesTitle),
                    icon: const Icon(Icons.star_border),
                  ),
                ],
                selected: {tab},
                onSelectionChanged: (s) =>
                    ref.read(selectedTabProvider.notifier).value = s.first,
              ),
              const LibraryToolbar(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            ref.read(libraryControllerProvider.notifier).importFromPicker(),
        icon: const Icon(Icons.add),
        label: Text(l10n.importAction),
      ),
      body: visible.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final failure = error is AppFailure ? error : const UnknownFailure();
          final message = failureMessage(failure, l10n);
          return EmptyState(
            icon: Icons.error_outline,
            title: message.title,
            body: message.body,
          );
        },
        data: (items) {
          if (items.isEmpty) {
            return _emptyFor(
              tab,
              query,
              l10n,
              inCollection: ref.watch(selectedCollectionProvider) != null,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) =>
                DocumentTile(document: items[i], onOpen: onOpenDocument),
          );
        },
      ),
    );
  }

  Widget _emptyFor(
    LibraryTab tab,
    String query,
    AppLocalizations l10n, {
    required bool inCollection,
  }) {
    if (query.trim().isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: l10n.noSearchResults,
        body: l10n.searchHint,
      );
    }
    if (inCollection && tab == LibraryTab.all) {
      return EmptyState(
        icon: Icons.folder_open,
        title: l10n.noDocumentsInFolder,
        body: l10n.moveToAction,
      );
    }
    return switch (tab) {
      LibraryTab.all => EmptyState(
        icon: Icons.picture_as_pdf_outlined,
        title: l10n.emptyLibraryTitle,
        body: l10n.emptyLibraryBody,
      ),
      LibraryTab.recents => EmptyState(
        icon: Icons.history,
        title: l10n.recentsTitle,
        body: l10n.noRecents,
      ),
      LibraryTab.favorites => EmptyState(
        icon: Icons.star_border,
        title: l10n.favoritesTitle,
        body: l10n.noFavorites,
      ),
    };
  }
}
