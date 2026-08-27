import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/errors/failure_messages.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/home/widgets/collection_bar.dart';
import 'package:folio/features/home/widgets/document_tile.dart';
import 'package:folio/features/home/widgets/empty_state.dart';
import 'package:folio/features/pages/providers.dart';
import 'package:folio/features/home/widgets/library_toolbar.dart';
import 'package:folio/domain/batch/batch_outcome.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'package:folio/features/automation/automation_screen.dart';
import 'package:folio/features/batch/batch_providers.dart';
import 'package:folio/features/batch/batch_sheet.dart';
import 'package:folio/features/viewer/widgets/protect_dialog.dart';
import 'package:folio/features/viewer/widgets/watermark_sheet.dart';
import 'package:folio/features/scanner/scanner_screen.dart';
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
        title: Text(
          ref.watch(librarySelectModeProvider)
              ? l10n.pagesSelectedCount(
                  ref.watch(librarySelectionProvider).length,
                )
              : l10n.libraryTitle,
        ),
        actions: [
          if (ref.watch(librarySelectModeProvider)) ...[
            TextButton(
              onPressed: ref.watch(librarySelectionProvider).length >= 2
                  ? () => _mergeSelected(context, ref, l10n)
                  : null,
              child: Text(l10n.libraryMergeSelected),
            ),
            IconButton(
              tooltip: l10n.batchTitle(
                ref.watch(librarySelectionProvider).length,
              ),
              icon: const Icon(Icons.playlist_add_check),
              onPressed: ref.watch(librarySelectionProvider).isEmpty
                  ? null
                  : () => _runBatch(context, ref, l10n),
            ),
            TextButton(
              onPressed: () {
                ref.read(librarySelectModeProvider.notifier).value = false;
                ref.read(librarySelectionProvider.notifier).value = const {};
              },
              child: Text(l10n.libraryExitSelect),
            ),
          ] else ...[
            IconButton(
              tooltip: l10n.automationTitle,
              icon: const Icon(Icons.auto_awesome_motion_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AutomationScreen(),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.scanTitle,
              icon: const Icon(Icons.document_scanner_outlined),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ScannerScreen(),
                  ),
                );
                await ref.read(libraryControllerProvider.notifier).refresh();
              },
            ),
            IconButton(
              tooltip: l10n.librarySelectMode,
              icon: const Icon(Icons.checklist),
              onPressed: () =>
                  ref.read(librarySelectModeProvider.notifier).value = true,
            ),
          ],
        ],
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

  /// Runs one operation over every selected document.
  ///
  /// The batch runs to completion; a document that fails is recorded and the
  /// rest continue. Stopping leaves everything already produced in place -
  /// undoing finished work would be a rollback nobody asked for.
  Future<void> _runBatch(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ids = ref.read(librarySelectionProvider).toList();
    if (ids.isEmpty) return;

    final action = await showBatchSheet(context, ids.length);
    if (action == null || !context.mounted) return;

    Watermark? mark;
    String? password;

    if (action == BatchAction.watermark) {
      mark = await showWatermarkSheet(context);
      if (mark == null || !context.mounted) return;
    }
    if (action == BatchAction.protect) {
      final request = await showProtectDialog(context);
      if (request == null || !context.mounted) return;
      password = request.userPassword;
    }

    final messenger = ScaffoldMessenger.of(context);
    var running = true;

    // A batch over ten documents with OCR is minutes of work. The banner is
    // the only sign anything is happening, and Stop has to actually stop.
    void showProgress(int done, int total) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.batchRunning(done, total)),
            duration: const Duration(minutes: 10),
            action: SnackBarAction(
              label: l10n.batchCancel,
              onPressed: () => running = false,
            ),
          ),
        );
    }

    showProgress(0, ids.length);

    final outcome = await ref
        .read(batchRepositoryProvider)
        .run(
          action: action,
          documentIds: ids,
          watermark: mark,
          password: password,
          onProgress: showProgress,
          shouldContinue: () => running,
        );

    await ref.read(libraryControllerProvider.notifier).refresh();
    if (!context.mounted) return;

    ref.read(librarySelectModeProvider.notifier).value = false;
    ref.read(librarySelectionProvider.notifier).value = const {};

    final details = batchSkipDetails(outcome, l10n);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            [
              batchSummary(outcome, l10n),
              if (details.isNotEmpty) details.join(' · '),
            ].join('\n'),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
  }

  Future<void> _mergeSelected(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ids = ref.read(librarySelectionProvider).toList();
    try {
      final merged = await ref
          .read(pageOperationsRepositoryProvider)
          .merge(documentIds: ids);
      await ref.read(libraryControllerProvider.notifier).refresh();

      ref.read(librarySelectModeProvider.notifier).value = false;
      ref.read(librarySelectionProvider.notifier).value = const {};

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pagesApplied(merged.displayName))),
      );
    } on AppFailure catch (f) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    }
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
