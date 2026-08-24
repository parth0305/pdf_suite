import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/errors/failure_messages.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/viewer/widgets/password_prompt.dart';
import 'package:folio/features/viewer/widgets/viewer_search_bar.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key, required this.document});

  final LibraryDocument document;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  final _controller = PdfViewerController();

  /// Created only once the viewer signals readiness: PdfTextSearcher's
  /// constructor dereferences controller.document, which is null until the
  /// document has loaded.
  PdfTextSearcher? _searcher;

  String? _path;
  AppFailure? _failure;
  bool _fullScreen = false;
  bool _searchOpen = false;
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searcher
      ?..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  /// Indirection so the paint callback can be registered before the searcher
  /// exists; it simply does nothing until the document is ready.
  void _paintSearchMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final path = await repo.resolveReadablePath(widget.document);
      // Recorded before rendering: opening is what makes it "recent", even if
      // the document later fails to render.
      await ref
          .read(libraryControllerProvider.notifier)
          .markOpened(widget.document.id);
      if (mounted) setState(() => _path = path);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_failure != null) {
      final message = failureMessage(_failure!, l10n);
      return Scaffold(
        appBar: AppBar(title: Text(widget.document.displayName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  message.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(message.body, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    if (_path == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: _fullScreen
          ? null
          : AppBar(
              title: Text(
                widget.document.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: l10n.viewerSearch,
                  icon: const Icon(Icons.search),
                  onPressed: _searcher == null
                      ? null
                      : () => setState(() => _searchOpen = !_searchOpen),
                ),
                IconButton(
                  tooltip: l10n.viewerZoomOut,
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () => _controller.zoomDown(),
                ),
                IconButton(
                  tooltip: l10n.viewerZoomIn,
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () => _controller.zoomUp(),
                ),
                IconButton(
                  tooltip: l10n.viewerFullScreen,
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () => setState(() => _fullScreen = true),
                ),
              ],
            ),
      body: Column(
        children: [
          if (_searchOpen && !_fullScreen && _searcher != null)
            ViewerSearchBar(
              searcher: _searcher!,
              onClose: () {
                _searcher!.resetTextSearch();
                setState(() => _searchOpen = false);
              },
            ),
          Expanded(
            child: PdfViewer.file(
              _path!,
              controller: _controller,
              passwordProvider: () => promptForPassword(context),
              params: PdfViewerParams(
                textSelectionParams: const PdfTextSelectionParams(
                  enabled: true,
                ),
                pagePaintCallbacks: [_paintSearchMatches],
                onViewerReady: (document, controller) {
                  if (!mounted || _searcher != null) return;
                  setState(() {
                    _searcher = PdfTextSearcher(controller)
                      ..addListener(_onSearchChanged);
                  });
                },
                onDocumentChanged: (doc) {
                  if (doc != null && mounted) {
                    setState(() => _totalPages = doc.pages.length);
                  }
                },
                onPageChanged: (pageNumber) {
                  if (pageNumber != null && mounted) {
                    setState(() => _currentPage = pageNumber);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _fullScreen || _totalPages == 0
          ? null
          : BottomAppBar(
              height: 48,
              child: Center(
                child: Text(
                  l10n.viewerPageIndicator(_currentPage, _totalPages),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
      floatingActionButton: _fullScreen
          ? FloatingActionButton.small(
              tooltip: l10n.viewerExitFullScreen,
              onPressed: () => setState(() => _fullScreen = false),
              child: const Icon(Icons.fullscreen_exit),
            )
          : null,
    );
  }
}
