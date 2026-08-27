import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/errors/failure_messages.dart';
import 'package:folio/domain/scanner/scanned_page.dart';
import 'package:folio/features/scanner/scanner_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Capture or import pages, reorder them, and save as a new PDF.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  bool _busy = false;

  /// Turns bytes into a page, or reports why it could not.
  ///
  /// `ScannedPage` parses the JPEG header in its constructor, so an image the
  /// PDF cannot carry is refused here rather than at save time - after ten
  /// more captures, when it is far less obvious which one was the problem.
  void _addBytes(List<List<int>> images, AppLocalizations l10n) {
    final pages = <ScannedPage>[];
    var refused = false;

    for (final bytes in images) {
      try {
        pages.add(ScannedPage(bytes));
      } on AppFailure {
        refused = true;
      }
    }

    if (pages.isNotEmpty) {
      ref.read(scanSessionProvider.notifier).addAll(pages);
    }
    if (refused && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.scanUnsupportedImage)));
    }
  }

  Future<void> _capture() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final shot = await ref.read(scanImageSourceProvider).capture();
      if (shot != null && mounted) _addBytes([shot], l10n);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final shots = await ref.read(scanImageSourceProvider).pickFromGallery();
      if (mounted && shots.isNotEmpty) _addBytes(shots, l10n);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final pages = ref.read(scanSessionProvider);
    if (pages.isEmpty) return;

    setState(() => _busy = true);
    try {
      final doc = await ref.read(scannerRepositoryProvider).save(pages);
      if (!mounted) return;

      ref.read(scanSessionProvider.notifier).clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.scanSaved(doc.displayName))));
      Navigator.of(context).pop();
    } on AppFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context)!;
    if (ref.read(scanSessionProvider).isEmpty) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.scanDiscardTitle),
        content: Text(l10n.scanDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(l10n.pagesDiscard),
          ),
        ],
      ),
    );

    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = ref.watch(scanSessionProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        // The navigator is captured BEFORE the await: reaching for it
        // afterwards is a use across an async gap that a `mounted` check on a
        // different object does not make safe.
        final navigator = Navigator.of(context);
        if (!await _confirmDiscard() || !mounted) return;

        ref.read(scanSessionProvider.notifier).clear();
        navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.scanTitle)),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            // Folio now PRODUCES documents with no text layer. Saying so here
            // costs one line; discovering it after scanning a contract costs
            // considerably more.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Text(
                l10n.scanNoTextWarning,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            Expanded(
              child: pages.isEmpty
                  ? Center(child: Text(l10n.scanEmpty))
                  : ReorderableListView.builder(
                      itemCount: pages.length,
                      onReorder: (from, to) {
                        // ReorderableListView reports the destination as an
                        // index in the list BEFORE the item is removed, so
                        // moving downward is one too far.
                        ref
                            .read(scanSessionProvider.notifier)
                            .move(from, to > from ? to - 1 : to);
                      },
                      itemBuilder: (context, i) => ListTile(
                        key: ValueKey(pages[i]),
                        leading: SizedBox(
                          width: 48,
                          height: 64,
                          child: Image.memory(
                            Uint8List.fromList(pages[i].jpeg),
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(l10n.scanPageLabel(i + 1)),
                        subtitle: Text(
                          '${pages[i].info.width} x ${pages[i].info.height}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l10n.scanRemove,
                          onPressed: () => ref
                              .read(scanSessionProvider.notifier)
                              .removeAt(i),
                        ),
                      ),
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(l10n.scanCamera),
                      onPressed: _busy ? null : _capture,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(l10n.scanImport),
                      onPressed: _busy ? null : _import,
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(l10n.scanSave),
                      onPressed: _busy || pages.isEmpty ? null : _save,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
