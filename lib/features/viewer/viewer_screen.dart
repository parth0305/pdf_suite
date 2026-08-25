import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/constants/breakpoints.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/errors/failure_messages.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:folio/engine/pdfrx_mappers.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/pages/providers.dart';
import 'package:folio/features/pages/split_sheet.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/features/viewer/annotation_providers.dart';
import 'package:folio/features/viewer/widgets/markup_toolbar.dart';
import 'package:folio/features/pages/widgets/page_grid.dart';
import 'package:folio/features/pages/widgets/page_toolbar.dart';
import 'package:folio/features/viewer/widgets/outline_panel.dart';
import 'package:folio/features/viewer/widgets/password_prompt.dart';
import 'package:folio/features/viewer/widgets/thumbnail_panel.dart';
import 'package:folio/features/viewer/widgets/viewer_search_bar.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

enum _SidePanel { none, thumbnails, outline }

enum _ViewerMode { read, pages, markup }

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

  PdfDocument? _document;
  List<OutlineNode> _outline = const [];

  String? _path;
  AppFailure? _failure;
  bool _fullScreen = false;
  bool _searchOpen = false;
  _SidePanel _panel = _SidePanel.none;
  _ViewerMode _mode = _ViewerMode.read;
  int _currentPage = 1;
  int _totalPages = 0;

  /// The live text selection, kept so the markup buttons know whether they can
  /// act and what to act on.
  PdfTextSelection? _selection;

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

  Future<void> _onReady(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    if (!mounted) return;
    final nodes = await document.loadOutline();
    if (!mounted) return;
    setState(() {
      _document = document;
      _outline = nodes.map(convertOutlineNode).toList();
      _searcher ??= PdfTextSearcher(controller)..addListener(_onSearchChanged);
    });
  }

  void _jumpToPage(int pageNumber) {
    _controller.goToPage(pageNumber: pageNumber);
    if (widthClassFor(MediaQuery.sizeOf(context).width) == WidthClass.compact) {
      Navigator.of(context).maybePop();
    }
  }

  Widget? _panelContent() {
    final doc = _document;
    return switch (_panel) {
      _SidePanel.none => null,
      _SidePanel.outline => OutlinePanel(
        nodes: _outline,
        onJump: (pageIndex) => _jumpToPage(pageIndex + 1),
      ),
      _SidePanel.thumbnails =>
        doc == null
            ? const Center(child: CircularProgressIndicator())
            : ThumbnailPanel(
                document: doc,
                currentPage: _currentPage,
                onJump: _jumpToPage,
              ),
    };
  }

  void _togglePanel(_SidePanel panel) {
    final isCompact =
        widthClassFor(MediaQuery.sizeOf(context).width) == WidthClass.compact;

    if (isCompact) {
      setState(() => _panel = panel);
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) =>
            SizedBox(height: 420, child: _panelContent() ?? const SizedBox()),
      ).whenComplete(() {
        if (mounted) setState(() => _panel = _SidePanel.none);
      });
    } else {
      setState(() => _panel = _panel == panel ? _SidePanel.none : panel);
    }
  }

  void _enterPagesMode() {
    ref
        .read(pageSessionProvider.notifier)
        .start(documentId: widget.document.id, pageCount: _totalPages);
    setState(() => _mode = _ViewerMode.pages);
  }

  Future<void> _leavePagesMode() async {
    final l10n = AppLocalizations.of(context)!;
    final dirty = ref.read(pageSessionProvider).session.isDirty;

    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.pagesDiscardPrompt),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.pagesDiscard),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) setState(() => _mode = _ViewerMode.read);
  }

  Future<void> _applyEdits() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(pageSessionProvider.notifier);
    final slots = ref.read(pageSessionProvider).session.slots;

    controller.setBusy(true);
    try {
      final created = await ref
          .read(pageOperationsRepositoryProvider)
          .apply(sourceDocumentId: widget.document.id, slots: slots);
      await ref.read(libraryControllerProvider.notifier).refresh();

      if (!mounted) return;
      setState(() => _mode = _ViewerMode.read);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pagesApplied(created.displayName))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      final message = failureMessage(f, l10n);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message.title)));
    } finally {
      controller.setBusy(false);
    }
  }

  Future<void> _extractSelection() async {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.read(pageSessionProvider);
    final slots = state.session.extract(state.selection);
    if (slots.isEmpty) return;

    try {
      final created = await ref
          .read(pageOperationsRepositoryProvider)
          .extractPages(sourceDocumentId: widget.document.id, slots: slots);
      await ref.read(libraryControllerProvider.notifier).refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pagesApplied(created.displayName))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      final message = failureMessage(f, l10n);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message.title)));
    }
  }

  void _enterMarkupMode() {
    ref.read(annotationSessionProvider.notifier).reset();
    setState(() => _mode = _ViewerMode.markup);
  }

  Future<void> _leaveMarkupMode() async {
    final l10n = AppLocalizations.of(context)!;
    if (ref.read(annotationSessionProvider).session.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.markupDiscardPrompt),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.pagesDiscard),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (!mounted) return;
    ref.read(annotationSessionProvider.notifier).reset();
    setState(() => _mode = _ViewerMode.read);
  }

  /// Turns the live selection into staged markup.
  ///
  /// Each selected range carries its page and a character span; the matching
  /// charRects are the geometry, already in PDF user space, so no conversion
  /// is needed on the way to /QuadPoints.
  Future<void> _markupSelection(MarkupKind kind) async {
    final selection = _selection;
    if (selection == null || !selection.hasSelectedText) return;

    final ranges = await selection.getSelectedTextRanges();
    if (!mounted) return;

    final controller = ref.read(annotationSessionProvider.notifier);
    for (final range in ranges) {
      final rects = range.pageText.charRects
          .sublist(range.start, range.end)
          .map(
            (r) => TextRect(
              left: r.left,
              top: r.top,
              right: r.right,
              bottom: r.bottom,
            ),
          )
          .toList();

      controller.addMarkup(
        kind: kind,
        pageIndex: range.pageText.pageNumber - 1,
        charRects: rects,
      );
    }
  }

  Future<void> _saveAnnotations() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(annotationSessionProvider.notifier);
    final annotations = ref.read(annotationSessionProvider).session.annotations;

    controller.setBusy(true);
    try {
      final created = await ref
          .read(annotationRepositoryProvider)
          .saveAnnotations(
            sourceDocumentId: widget.document.id,
            annotations: annotations,
          );
      await ref.read(libraryControllerProvider.notifier).refresh();

      if (!mounted) return;
      controller.reset();
      setState(() => _mode = _ViewerMode.read);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.markupSaved(created.displayName))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    } finally {
      controller.setBusy(false);
    }
  }

  Future<void> _splitDocument() async {
    final l10n = AppLocalizations.of(context)!;
    final plan = await showSplitSheet(context, pageCount: _totalPages);
    if (plan == null || !mounted) return;

    try {
      final parts = await ref
          .read(pageOperationsRepositoryProvider)
          .split(sourceDocumentId: widget.document.id, groups: plan.groups);
      await ref.read(libraryControllerProvider.notifier).refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.splitOutputCount(parts.length))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    }
  }

  Future<void> _insertPages() async {
    final l10n = AppLocalizations.of(context)!;
    final all = ref.read(libraryControllerProvider).value ?? const [];
    final others = all.where((d) => d.id != widget.document.id).toList();

    if (others.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.insertNoOtherDocuments)));
      return;
    }

    final chosen = await showModalBottomSheet<LibraryDocument>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.insertChooseDocument,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final d in others)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(d.displayName),
                onTap: () => Navigator.of(context).pop(d),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    // Open the chosen document only to learn its page count; the editor
    // reopens it when materialising.
    final repo = ref.read(libraryRepositoryProvider);
    final engine = PdfrxEngine();
    try {
      final handle = await engine.open(
        FileSource(await repo.resolveReadablePath(chosen)),
      );
      final session = ref.read(pageSessionProvider);
      final at = session.selection.isEmpty
          ? session.session.slots.length
          : session.selection.reduce((a, b) => a < b ? a : b);

      ref
          .read(pageSessionProvider.notifier)
          .insertFrom(chosen.id, handle.pageCount, at: at);
      await engine.close(handle);
    } on AppFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_failure != null) return _errorScaffold(context, l10n);
    if (_path == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isCompact =
        widthClassFor(MediaQuery.sizeOf(context).width) == WidthClass.compact;
    final dockedPanel = isCompact ? null : _panelContent();

    final viewer = PdfViewer.file(
      _path!,
      controller: _controller,
      passwordProvider: () => promptForPassword(context),
      params: PdfViewerParams(
        textSelectionParams: PdfTextSelectionParams(
          enabled: true,
          onTextSelectionChange: (selection) {
            if (mounted) setState(() => _selection = selection);
          },
        ),
        pagePaintCallbacks: [_paintSearchMatches],
        onViewerReady: _onReady,
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
    );

    return Scaffold(
      appBar: _fullScreen ? null : _appBar(l10n),
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
            child: _mode == _ViewerMode.pages
                ? (_document == null
                      ? const Center(child: CircularProgressIndicator())
                      : PageGrid(document: _document!))
                : dockedPanel == null
                ? viewer
                : Row(
                    children: [
                      SizedBox(width: 220, child: dockedPanel),
                      const VerticalDivider(width: 1),
                      Expanded(child: viewer),
                    ],
                  ),
          ),
          if (_mode == _ViewerMode.markup)
            MarkupToolbar(
              hasSelection: _selection?.hasSelectedText ?? false,
              onMarkup: _markupSelection,
              onSave: _saveAnnotations,
            ),
          if (_mode == _ViewerMode.pages)
            PageToolbar(
              onApply: _applyEdits,
              onExtract: _extractSelection,
              onInsert: _insertPages,
            ),
        ],
      ),
      bottomNavigationBar:
          _fullScreen || _totalPages == 0 || _mode != _ViewerMode.read
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

  PreferredSizeWidget _appBar(AppLocalizations l10n) => AppBar(
    title: Text(
      widget.document.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    leading: switch (_mode) {
      _ViewerMode.pages => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _leavePagesMode,
      ),
      _ViewerMode.markup => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _leaveMarkupMode,
      ),
      _ViewerMode.read => null,
    },
    actions: [
      IconButton(
        tooltip: _mode == _ViewerMode.pages ? l10n.readMode : l10n.pagesMode,
        icon: Icon(
          _mode == _ViewerMode.pages
              ? Icons.menu_book
              : Icons.dashboard_customize,
        ),
        isSelected: _mode == _ViewerMode.pages,
        onPressed: _totalPages == 0
            ? null
            : () => _mode == _ViewerMode.pages
                  ? _leavePagesMode()
                  : _enterPagesMode(),
      ),
      if (_mode == _ViewerMode.read)
        IconButton(
          tooltip: l10n.markupMode,
          icon: const Icon(Icons.format_color_fill),
          onPressed: _totalPages == 0 ? null : _enterMarkupMode,
        ),
      if (_mode == _ViewerMode.pages)
        IconButton(
          tooltip: l10n.pagesSplit,
          icon: const Icon(Icons.call_split),
          onPressed: _totalPages == 0 ? null : _splitDocument,
        ),
      if (_mode == _ViewerMode.read) ...[
        IconButton(
          tooltip: l10n.viewerThumbnails,
          icon: const Icon(Icons.grid_view),
          isSelected: _panel == _SidePanel.thumbnails,
          onPressed: () => _togglePanel(_SidePanel.thumbnails),
        ),
        IconButton(
          tooltip: l10n.viewerOutline,
          icon: const Icon(Icons.list),
          isSelected: _panel == _SidePanel.outline,
          onPressed: () => _togglePanel(_SidePanel.outline),
        ),
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
    ],
  );

  Scaffold _errorScaffold(BuildContext context, AppLocalizations l10n) {
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
}
