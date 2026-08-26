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
import 'package:folio/features/viewer/annotation_edit_providers.dart';
import 'package:folio/features/viewer/widgets/annotation_edit_toolbar.dart';
import 'package:folio/features/viewer/widgets/annotation_selection_overlay.dart';
import 'package:folio/features/viewer/signature_providers.dart';
import 'package:folio/features/viewer/widgets/drawing_surface.dart';
import 'package:folio/features/viewer/widgets/signature_placement_surface.dart';
import 'package:folio/features/viewer/widgets/note_dialog.dart';
import 'package:folio/features/viewer/widgets/signature_sheet.dart';
import 'package:folio/features/viewer/widgets/stamp_picker.dart';
import 'package:folio/features/viewer/watermark_providers.dart';
import 'package:folio/features/viewer/widgets/tap_placement_surface.dart';
import 'package:folio/features/viewer/widgets/watermark_sheet.dart';
import 'package:folio/features/viewer/widgets/drawing_toolbar.dart';
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

enum _ViewerMode {
  read,
  pages,
  markup,
  draw,
  annotations,
  signature,
  note,
  stamp,
}

enum _AnnotateTool {
  markup,
  draw,
  annotations,
  signature,
  note,
  stamp,
  watermark,
}

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
  DrawingKind _tool = DrawingKind.ink;
  int _drawColour = drawingColours.first;
  double _drawStrokeWidth = 2;
  StampPreset _stampPreset = StampPreset.approved;
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

  void _enterDrawMode() {
    ref.read(annotationSessionProvider.notifier).reset();
    setState(() => _mode = _ViewerMode.draw);
  }

  Future<void> _leaveDrawMode() async {
    final l10n = AppLocalizations.of(context)!;
    if (ref.read(annotationSessionProvider).session.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.drawDiscardPrompt),
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

  Future<void> _applyWatermark() async {
    final l10n = AppLocalizations.of(context)!;
    final mark = await showWatermarkSheet(context);
    if (mark == null || !mounted) return;

    try {
      final marked = await ref
          .read(watermarkRepositoryProvider)
          .apply(widget.document.id, mark);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      // Show the result rather than the document we started from.
      final path = await ref
          .read(libraryRepositoryProvider)
          .resolveReadablePath(marked);
      if (!mounted) return;

      setState(() => _path = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.watermarkApplied(marked.displayName))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    }
  }

  void _enterNoteMode() {
    ref.read(annotationSessionProvider.notifier).reset();
    setState(() => _mode = _ViewerMode.note);
  }

  void _enterStampMode() {
    ref.read(annotationSessionProvider.notifier).reset();
    setState(() {
      _stampPreset = StampPreset.approved;
      _mode = _ViewerMode.stamp;
    });
  }

  Future<void> _leaveStagingMode() async {
    final l10n = AppLocalizations.of(context)!;
    if (ref.read(annotationSessionProvider).session.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.drawDiscardPrompt),
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

  Future<void> _enterSignatureMode() async {
    ref.read(annotationSessionProvider.notifier).reset();
    ref.read(signingProvider.notifier).select(null);

    final chose = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => const SignatureSheet(),
    );
    // Entering with nothing chosen would leave the user in a mode that does
    // nothing when they drag.
    if (chose != true || !mounted) return;
    setState(() => _mode = _ViewerMode.signature);
  }

  Future<void> _leaveSignatureMode() async {
    final l10n = AppLocalizations.of(context)!;
    if (ref.read(annotationSessionProvider).session.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.signDiscardPrompt),
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

  Future<void> _enterAnnotationsMode() async {
    final controller = ref.read(annotationEditProvider.notifier);
    controller.reset();
    try {
      await controller.load(widget.document.id);
    } on Exception {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.annotationsEmpty)));
      return;
    }
    if (!mounted) return;
    setState(() => _mode = _ViewerMode.annotations);
  }

  Future<void> _leaveAnnotationsMode() async {
    final l10n = AppLocalizations.of(context)!;
    if (ref.read(annotationEditProvider).session.isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.annotationsDiscardPrompt),
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
    ref.read(annotationEditProvider.notifier).reset();
    setState(() => _mode = _ViewerMode.read);
  }

  Future<void> _saveAnnotationEdits() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(annotationEditProvider.notifier);
    final session = ref.read(annotationEditProvider).session;

    controller.setBusy(true);
    try {
      final saved = await ref
          .read(annotationEditRepositoryProvider)
          .save(
            documentId: widget.document.id,
            deleted: session.deleted,
            restyled: session.restyled,
            moved: session.moved,
          );
      await ref.read(libraryControllerProvider.notifier).refresh();

      if (!mounted) return;
      // An in-place save keeps this document's row but gives it new content at
      // a new content-addressed path. Re-resolving rebuilds PdfViewer.file;
      // without it the viewer keeps rendering the superseded file.
      final path = await ref
          .read(libraryRepositoryProvider)
          .resolveReadablePath(saved);
      if (!mounted) return;

      controller.reset();
      setState(() {
        _path = path;
        _mode = _ViewerMode.read;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.annotationsSaved(saved.displayName))),
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
        // Only present in draw mode: in read mode there is no overlay at all,
        // so it cannot compete with the viewer for scroll or pinch gestures.
        pageOverlaysBuilder:
            (_mode != _ViewerMode.draw &&
                _mode != _ViewerMode.annotations &&
                _mode != _ViewerMode.signature &&
                _mode != _ViewerMode.note &&
                _mode != _ViewerMode.stamp)
            ? null
            : (context, pageRect, page) => [
                // The overlay is positioned at the page, so its own local
                // space starts at the page's top-left. Passing the viewer
                // space rect would offset every stroke and every hit test by
                // the page origin.
                if (_mode == _ViewerMode.note || _mode == _ViewerMode.stamp)
                  TapPlacementSurface(
                    pageRect: Offset.zero & pageRect.size,
                    pageWidthPt: page.width,
                    pageHeightPt: page.height,
                    pageIndex: page.pageNumber - 1,
                    onTap: (pt) async {
                      final pageIndex = page.pageNumber - 1;
                      if (_mode == _ViewerMode.stamp) {
                        ref
                            .read(annotationSessionProvider.notifier)
                            .addStamp(
                              preset: _stampPreset,
                              pageIndex: pageIndex,
                              anchorPt: pt,
                            );
                        return;
                      }
                      final text = await showNoteDialog(context);
                      if (text == null || !mounted) return;
                      ref
                          .read(annotationSessionProvider.notifier)
                          .addNote(
                            pageIndex: pageIndex,
                            anchorPt: pt,
                            contents: text,
                          );
                    },
                  )
                else if (_mode == _ViewerMode.signature)
                  SignaturePlacementSurface(
                    pageRect: Offset.zero & pageRect.size,
                    pageWidthPt: page.width,
                    pageHeightPt: page.height,
                    pageIndex: page.pageNumber - 1,
                  )
                else if (_mode == _ViewerMode.draw)
                  DrawingSurface(
                    tool: _tool,
                    colorArgb: _drawColour,
                    strokeWidth: _drawStrokeWidth,
                    pageRect: Offset.zero & pageRect.size,
                    pageWidthPt: page.width,
                    pageHeightPt: page.height,
                    pageIndex: page.pageNumber - 1,
                  )
                else
                  AnnotationSelectionOverlay(
                    pageRect: Offset.zero & pageRect.size,
                    pageWidthPt: page.width,
                    pageHeightPt: page.height,
                    pageIndex: page.pageNumber - 1,
                  ),
              ],
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
          if (_mode == _ViewerMode.note || _mode == _ViewerMode.stamp)
            _stagingToolbar(l10n),
          if (_mode == _ViewerMode.signature) _signatureToolbar(l10n),
          if (_mode == _ViewerMode.annotations)
            AnnotationEditToolbar(
              onSave: _saveAnnotationEdits,
              pageIndex: _currentPage - 1,
            ),
          if (_mode == _ViewerMode.draw)
            DrawingToolbar(
              tool: _tool,
              colorArgb: _drawColour,
              strokeWidth: _drawStrokeWidth,
              onToolChanged: (t) => setState(() => _tool = t),
              onColourChanged: (c) => setState(() => _drawColour = c),
              onStrokeWidthChanged: (w) => setState(() => _drawStrokeWidth = w),
              onSave: _saveAnnotations,
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

  Widget _stagingToolbar(AppLocalizations l10n) {
    final state = ref.watch(annotationSessionProvider);
    final controller = ref.read(annotationSessionProvider.notifier);
    final isStamp = _mode == _ViewerMode.stamp;

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
                      state.session.isEmpty
                          ? (isStamp ? l10n.stampPlaceHint : l10n.notePlaceHint)
                          : l10n.markupCount(state.session.annotations.length),
                      style: Theme.of(context).textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: l10n.drawUndo,
                    icon: const Icon(Icons.undo),
                    onPressed: state.session.canUndo ? controller.undo : null,
                  ),
                  // Pinned, never inside a scrolling row.
                  FilledButton.icon(
                    onPressed: state.session.isDirty && !state.busy
                        ? _saveAnnotations
                        : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.drawSave),
                  ),
                ],
              ),
              if (isStamp) ...[
                const SizedBox(height: 4),
                StampPicker(
                  selected: _stampPreset,
                  onSelected: (p) => setState(() => _stampPreset = p),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _signatureToolbar(AppLocalizations l10n) {
    final state = ref.watch(annotationSessionProvider);
    final controller = ref.read(annotationSessionProvider.notifier);
    final chosen = ref.watch(signingProvider).chosen;

    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  state.session.isEmpty
                      ? '${chosen?.label ?? ''} · ${l10n.signPlaceHint}'
                      : l10n.markupCount(state.session.annotations.length),
                  style: Theme.of(context).textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l10n.drawUndo,
                icon: const Icon(Icons.undo),
                onPressed: state.session.canUndo ? controller.undo : null,
              ),
              // Pinned, never inside a scrolling row.
              FilledButton.icon(
                onPressed: state.session.isDirty && !state.busy
                    ? _saveAnnotations
                    : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.drawSave),
              ),
            ],
          ),
        ),
      ),
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
      _ViewerMode.draw => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _leaveDrawMode,
      ),
      _ViewerMode.annotations => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _leaveAnnotationsMode,
      ),
      _ViewerMode.signature => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _leaveSignatureMode,
      ),
      _ViewerMode.note || _ViewerMode.stamp => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _leaveStagingMode,
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
      // One menu rather than one icon per tool: the action bar was already at
      // the width limit, and a second annotation icon overflowed it. Sticky
      // notes and stamps land here too rather than pushing it over again.
      if (_mode == _ViewerMode.read)
        PopupMenuButton<_AnnotateTool>(
          tooltip: l10n.annotateMode,
          icon: const Icon(Icons.edit_outlined),
          enabled: _totalPages != 0,
          onSelected: (tool) => switch (tool) {
            _AnnotateTool.markup => _enterMarkupMode(),
            _AnnotateTool.draw => _enterDrawMode(),
            _AnnotateTool.annotations => _enterAnnotationsMode(),
            _AnnotateTool.signature => _enterSignatureMode(),
            _AnnotateTool.note => _enterNoteMode(),
            _AnnotateTool.stamp => _enterStampMode(),
            _AnnotateTool.watermark => _applyWatermark(),
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _AnnotateTool.markup,
              child: ListTile(
                leading: const Icon(Icons.format_color_fill),
                title: Text(l10n.markupMode),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _AnnotateTool.draw,
              child: ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: Text(l10n.drawMode),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _AnnotateTool.note,
              child: ListTile(
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: Text(l10n.noteMode),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _AnnotateTool.stamp,
              child: ListTile(
                leading: const Icon(Icons.approval_outlined),
                title: Text(l10n.stampMode),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _AnnotateTool.watermark,
              child: ListTile(
                leading: const Icon(Icons.branding_watermark_outlined),
                title: Text(l10n.watermarkMode),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _AnnotateTool.signature,
              child: ListTile(
                leading: const Icon(Icons.draw),
                title: Text(l10n.signMode),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _AnnotateTool.annotations,
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(l10n.annotationsMode),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
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
