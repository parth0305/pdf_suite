import 'dart:io';

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
import 'package:folio/features/viewer/widgets/custom_stamp_dialog.dart';
import 'package:folio/data/signature/signature_photo_source.dart';
import 'package:folio/features/scanner/scanner_providers.dart';
import 'package:folio/features/viewer/widgets/image_placement_surface.dart';
import 'package:folio/features/viewer/metadata_providers.dart';
import 'package:folio/features/viewer/widgets/metadata_dialog.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'package:folio/features/viewer/unlock_providers.dart';
import 'package:folio/features/viewer/widgets/unlock_dialog.dart';
import 'package:folio/features/viewer/widgets/document_actions_sheet.dart';
import 'package:folio/features/viewer/widgets/protect_dialog.dart';
import 'package:folio/features/viewer/compression_providers.dart';
import 'package:folio/features/viewer/export_providers.dart';
import 'package:folio/features/viewer/ocr_providers.dart';
import 'package:folio/features/viewer/redaction_providers.dart';
import 'package:folio/features/viewer/widgets/redact_confirm_dialog.dart';
import 'package:folio/features/viewer/widgets/redact_overlay.dart';
import 'package:folio/features/viewer/widgets/signature_sheet.dart';
import 'package:folio/features/viewer/widgets/stamp_picker.dart';
import 'package:folio/features/viewer/protection_providers.dart';
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
  redact,
  insertImage,
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

  /// Set when the user chose custom wording or today's date. Null means the
  /// preset speaks for itself.
  String? _stampCustomLabel;

  /// The decoded picture waiting to be placed.
  DecodedImage? _insertImage;
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

  /// Compresses only after showing what it will save.
  ///
  /// The work is done once and the result carried into the dialog, so the file
  /// the user accepts is exactly the one that was measured - not a second
  /// compression that might differ.
  /// Hands the document to the operating system's print dialog.
  ///
  /// This is one of only two places a document leaves the device, so the
  /// refusal path matters: a protected document is stopped here rather than
  /// failing inside the print service where nothing explains why.
  /// Whether the app bar can carry every view control.
  ///
  /// In read mode the bar held eight buttons, which is too many across a
  /// phone: they crowd to the point where the target sizes shrink and the
  /// title has nowhere to go. Below this width, thumbnails, outline, full
  /// screen and the two zoom buttons move into the actions sheet - pinch
  /// already zooms, so the zoom pair is no loss on touch.
  ///
  /// 600 is the same breakpoint AdaptiveScaffold uses for its navigation rail.
  bool get _hasRoomForFullToolbar => MediaQuery.sizeOf(context).width >= 600;

  Future<void> _runAction(DocumentAction action) async {
    switch (action) {
      case DocumentAction.thumbnails:
        setState(() => _panel = _SidePanel.thumbnails);
      case DocumentAction.outline:
        setState(() => _panel = _SidePanel.outline);
      case DocumentAction.fullScreen:
        setState(() => _fullScreen = true);
      case DocumentAction.markup:
        _enterMarkupMode();
      case DocumentAction.draw:
        _enterDrawMode();
      case DocumentAction.insertImage:
        await _enterInsertImageMode();
      case DocumentAction.annotations:
        await _enterAnnotationsMode();
      case DocumentAction.signature:
        await _enterSignatureMode();
      case DocumentAction.note:
        _enterNoteMode();
      case DocumentAction.stamp:
        _enterStampMode();
      case DocumentAction.metadata:
        await _editMetadata();
      case DocumentAction.watermark:
        await _applyWatermark();
      case DocumentAction.imageWatermark:
        await _applyImageWatermark();
      case DocumentAction.removeWatermark:
        await _removeWatermark();
      case DocumentAction.protect:
        await _protectDocument();
      case DocumentAction.unlock:
        await _unlockDocument();
      case DocumentAction.redact:
        _enterRedactMode();
      case DocumentAction.ocr:
        await _runOcr();
      case DocumentAction.compress:
        await _compressDocument();
      case DocumentAction.print:
        await _printDocument();
      case DocumentAction.share:
        await _shareDocument();
    }
  }

  Future<void> _printDocument() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final export = await ref
          .read(exportRepositoryProvider)
          .prepare(widget.document.id);

      final refusal = ref.read(exportRepositoryProvider).refusalFor(export);
      if (refusal != null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.printProtected)));
        return;
      }

      await ref.read(platformExportProvider).print(export);
    } on AppFailure catch (f) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(f, l10n).title)),
      );
    } on Object {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.printFailed)));
    }
  }

  /// Hands the document to the system share sheet.
  ///
  /// An encrypted document shares perfectly well - it stays encrypted - so
  /// there is no refusal here, unlike printing.
  Future<void> _shareDocument() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    // iPad anchors the share sheet to whatever was tapped.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    try {
      final export = await ref
          .read(exportRepositoryProvider)
          .prepare(widget.document.id);

      if (!mounted) return;
      // Names which document is going, because operations leave the original
      // alongside the result and the two look alike in a list.
      // Names the document AND says plainly that this is one of the two
      // places a document leaves Folio. PRIVACY.md makes the same promise;
      // this is where the user actually sees it.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.shareWhich(export.displayName)}\n${l10n.shareLeavesDevice}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );

      await ref.read(platformExportProvider).share(export, origin: origin);
    } on AppFailure catch (f) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(f, l10n).title)),
      );
    }
  }

  /// Removes a watermark Folio applied.
  ///
  /// Folio can only remove its own: it names its watermark resources, which is
  /// what makes them identifiable with certainty. A mark another tool applied
  /// leaves no such marker, and the refusal says so rather than reporting a
  /// success that removed nothing.
  /// Picks an image, then lets the user drag a box for it.
  ///
  /// The picture is decoded here rather than at placement time so a file that
  /// cannot be read fails before the user has chosen where to put it.
  Future<void> _enterInsertImageMode() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final picked = await ref.read(scanImageSourceProvider).pickFromGallery();
    if (picked.isEmpty || !mounted) return;

    try {
      final decoded = await decodeRgba(picked.first);
      if (!mounted) return;

      setState(() {
        _insertImage = decoded;
        _mode = _ViewerMode.insertImage;
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.insertImageHint)));
    } on Object {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.insertImageUnsupported)),
      );
    }
  }

  /// Edits the document's title, author, subject and keywords.
  Future<void> _editMetadata() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final current = await ref
          .read(metadataRepositoryProvider)
          .read(widget.document.id);
      if (!mounted) return;

      final edited = await showMetadataDialog(context, current);
      if (edited == null || !mounted) return;

      final saved = await ref
          .read(metadataRepositoryProvider)
          .save(widget.document.id, edited);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.metadataSaved(saved.displayName))),
      );
    } on ArgumentError {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.metadataEmpty)));
    } on AppFailure catch (f) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(f, l10n).title)),
      );
    }
  }

  /// Stamps a chosen image across every page.
  ///
  /// No placement step, unlike inserting an image: a watermark goes in the
  /// same place on every page by definition, so asking where would be asking
  /// a question with one answer.
  Future<void> _applyImageWatermark() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final picked = await ref.read(scanImageSourceProvider).pickFromGallery();
    if (picked.isEmpty || !mounted) return;

    try {
      final decoded = await decodeRgba(picked.first);
      if (!mounted) return;

      final marked = await ref
          .read(watermarkRepositoryProvider)
          .applyImage(
            widget.document.id,
            ImageWatermark(
              rgba: decoded.rgba,
              pixelWidth: decoded.width,
              pixelHeight: decoded.height,
            ),
          );
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.watermarkImageApplied(marked.displayName))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(f, l10n).title)),
      );
    } on Object {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.watermarkImageUnusable)),
      );
    }
  }

  /// Removes password protection, given the password.
  ///
  /// Folio stores no passwords and cannot open a document without one - that
  /// is the whole point of the feature this undoes. So it asks.
  Future<void> _unlockDocument() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    final password = await showUnlockDialog(context);
    if (password == null || !mounted) return;

    try {
      final unlocked = await ref
          .read(unlockRepositoryProvider)
          .unlock(widget.document.id, password);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.unlockDone(unlocked.displayName))),
      );
    } on WrongPassword {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.unlockWrong)));
    } on UnsupportedPdfStructure {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.unlockNotProtected)));
    } on AppFailure catch (f) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(f, l10n).title)),
      );
    }
  }

  Future<void> _removeWatermark() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final cleaned = await ref
          .read(watermarkRepositoryProvider)
          .remove(widget.document.id);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.watermarkRemoved(cleaned.displayName))),
      );
    } on UnsupportedPdfStructure {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.watermarkNoneFound),
          duration: const Duration(seconds: 6),
        ),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(f, l10n).title)),
      );
    }
  }

  Future<void> _compressDocument() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.compressChecking),
        duration: const Duration(minutes: 2),
      ),
    );

    try {
      final result = await ref
          .read(compressionRepositoryProvider)
          .analyse(widget.document.id);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();

      // An already-compressed document is the common case for scans, and a
      // button that appears to do nothing reads as broken.
      if (!result.worthDoing) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.compressNothing)));
        return;
      }

      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l10n.compressMode),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.compressOffer(
                  _formatBytes(result.savedBytes),
                  (result.savedFraction * 100).toStringAsFixed(0),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.compressLossless,
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: Text(l10n.compressApply),
            ),
          ],
        ),
      );

      if (accepted != true || !mounted) return;

      final compressed = await ref
          .read(compressionRepositoryProvider)
          .save(widget.document.id, result);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.compressDone(compressed.displayName))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  /// Word positions come from hOCR, which only Android can supply: the iOS
  /// plugin's hOCR call blocks the platform thread indefinitely.
  bool get _hasWordPositions => Platform.isAndroid;

  /// Tesseract is bundled for Android and iOS only; there is no Windows
  /// implementation, so the entry is disabled rather than failing on tap.
  bool get _ocrAvailable => Platform.isAndroid || Platform.isIOS;

  Future<void> _runOcr() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    if (!_ocrAvailable) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ocrUnavailable)));
      return;
    }

    // Recognition takes seconds per page, so the banner is not decoration -
    // without it the app looks frozen.
    //
    // On a platform that cannot report word positions the result is a weaker
    // text layer, and saying so here is what makes the claim in FEATURES.md
    // and ARCHITECTURE.md true. Without it the documentation described a
    // message that did not exist.
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _hasWordPositions
              ? l10n.ocrRunning
              : '${l10n.ocrRunning}\n${l10n.ocrApproximate}',
        ),
        duration: const Duration(minutes: 5),
      ),
    );

    try {
      final recognised = await ref
          .read(ocrRepositoryProvider)
          .recognise(widget.document.id);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.ocrDone(recognised.displayName))),
        );
    } on ArgumentError {
      // Thrown when no page yielded any text at all.
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.ocrNothingFound)));
    } on AppFailure catch (f) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    }
  }

  void _enterRedactMode() {
    ref.read(redactionSessionProvider.notifier).clear();
    setState(() => _mode = _ViewerMode.redact);
  }

  Future<void> _exitRedactMode() async {
    final l10n = AppLocalizations.of(context)!;

    if (ref.read(redactionSessionProvider).isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l10n.redactDiscardTitle),
          content: Text(l10n.redactDiscardBody),
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
      if (discard != true) return;
    }
    if (!mounted) return;

    ref.read(redactionSessionProvider.notifier).clear();
    setState(() => _mode = _ViewerMode.read);
  }

  Future<void> _applyRedactions() async {
    final l10n = AppLocalizations.of(context)!;
    final boxes = ref.read(redactionSessionProvider);

    if (boxes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.redactNone)));
      return;
    }

    if (!await showRedactConfirmDialog(context, boxes.length) || !mounted) {
      return;
    }

    try {
      final redacted = await ref
          .read(redactionRepositoryProvider)
          .apply(widget.document.id, boxes);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      ref.read(redactionSessionProvider.notifier).clear();
      setState(() => _mode = _ViewerMode.read);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.redactDone(redacted.displayName))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    }
  }

  /// The back button shared by every editing mode.
  ///
  /// Eight copies of this existed, none with a tooltip - a screen reader
  /// announced each as "button" and nothing more. One helper fixes the label
  /// and the duplication together.
  Widget _leaveModeButton(VoidCallback onPressed, AppLocalizations l10n) =>
      IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: l10n.viewerLeaveMode,
        onPressed: onPressed,
      );

  Widget _redactToolbar(AppLocalizations l10n) {
    final count = ref.watch(redactionSessionProvider).length;

    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.cancelAction,
              onPressed: _exitRedactMode,
            ),
            Expanded(
              child: Text(
                count == 0 ? l10n.redactHint : '$count',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: count == 0
                  ? null
                  : () => ref.read(redactionSessionProvider.notifier).clear(),
              child: Text(l10n.redactClear),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.format_color_reset_outlined),
              label: Text(l10n.redactApply),
              onPressed: count == 0 ? null : _applyRedactions,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _protectDocument() async {
    final l10n = AppLocalizations.of(context)!;
    final request = await showProtectDialog(context);
    if (request == null || !mounted) return;

    try {
      final protected = await ref
          .read(protectionRepositoryProvider)
          .protect(widget.document.id, request);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.protectDone(protected.displayName))),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(f, l10n).title)));
    }
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
      _stampCustomLabel = null;
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
      // Signature placement goes through the same save path as markup, but
      // "Marked up X" is the wrong word for it.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mode == _ViewerMode.signature
                ? l10n.signSaved(created.displayName)
                : l10n.markupSaved(created.displayName),
          ),
        ),
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
                _mode != _ViewerMode.stamp &&
                _mode != _ViewerMode.redact &&
                _mode != _ViewerMode.insertImage)
            ? null
            : (context, pageRect, page) => [
                // The overlay is positioned at the page, so its own local
                // space starts at the page's top-left. Passing the viewer
                // space rect would offset every stroke and every hit test by
                // the page origin.
                if (_mode == _ViewerMode.insertImage && _insertImage != null)
                  ImagePlacementSurface(
                    pageRect: Offset.zero & pageRect.size,
                    pageWidthPt: page.width,
                    pageHeightPt: page.height,
                    pageIndex: page.pageNumber - 1,
                    rgba: _insertImage!.rgba,
                    pixelWidth: _insertImage!.width,
                    pixelHeight: _insertImage!.height,
                  )
                else if (_mode == _ViewerMode.redact)
                  RedactOverlay(
                    pageRect: Offset.zero & pageRect.size,
                    pageWidthPt: page.width,
                    pageHeightPt: page.height,
                    pageIndex: page.pageNumber - 1,
                  )
                else if (_mode == _ViewerMode.note ||
                    _mode == _ViewerMode.stamp)
                  TapPlacementSurface(
                    pageRect: Offset.zero & pageRect.size,
                    pageWidthPt: page.width,
                    pageHeightPt: page.height,
                    pageIndex: page.pageNumber - 1,
                    onTap: (pt) async {
                      final pageIndex = page.pageNumber - 1;
                      if (_mode == _ViewerMode.stamp) {
                        // A null custom label means the preset's own wording,
                        // so one call serves preset, custom and date stamps.
                        ref
                            .read(annotationSessionProvider.notifier)
                            .addStamp(
                              preset: _stampPreset,
                              pageIndex: pageIndex,
                              anchorPt: pt,
                              customLabel: _stampCustomLabel,
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
          if (_mode == _ViewerMode.redact) _redactToolbar(l10n),
          if (_mode == _ViewerMode.note ||
              _mode == _ViewerMode.stamp ||
              _mode == _ViewerMode.insertImage)
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
                Row(
                  children: [
                    Expanded(
                      child: StampPicker(
                        selected: _stampPreset,
                        onSelected: (p) => setState(() {
                          _stampPreset = p;
                          // Choosing a preset clears custom wording: the
                          // picker showing APPROVED while the page gets
                          // "PAID" would be a lie about what will happen.
                          _stampCustomLabel = null;
                        }),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.stampCustom,
                      isSelected: _stampCustomLabel != null,
                      icon: const Icon(Icons.edit_note),
                      onPressed: () async {
                        final label = await showCustomStampDialog(context);
                        if (label == null || !mounted) return;
                        setState(() => _stampCustomLabel = label);
                      },
                    ),
                  ],
                ),
                if (_stampCustomLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _stampCustomLabel!,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
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
      _ViewerMode.pages => _leaveModeButton(_leavePagesMode, l10n),
      _ViewerMode.markup => _leaveModeButton(_leaveMarkupMode, l10n),
      _ViewerMode.draw => _leaveModeButton(_leaveDrawMode, l10n),
      _ViewerMode.redact => _leaveModeButton(_exitRedactMode, l10n),
      _ViewerMode.insertImage => _leaveModeButton(_leaveStagingMode, l10n),
      _ViewerMode.annotations => _leaveModeButton(_leaveAnnotationsMode, l10n),
      _ViewerMode.signature => _leaveModeButton(_leaveSignatureMode, l10n),
      _ViewerMode.note ||
      _ViewerMode.stamp => _leaveModeButton(_leaveStagingMode, l10n),
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
      // Print and share sit in the same menu, for the same width reason.
      // They are the only two actions here that send the document off the
      // device, which is why the menu names them plainly rather than using
      // bare icons.
      // One menu rather than one icon per tool: the action bar was already at
      // the width limit, and a second annotation icon overflowed it. Sticky
      // notes and stamps land here too rather than pushing it over again.
      if (_mode == _ViewerMode.read)
        IconButton(
          tooltip: l10n.actionsTitle,
          icon: const Icon(Icons.more_horiz),
          onPressed: _totalPages == 0
              ? null
              : () async {
                  // On a phone the View group joins the sheet, because those
                  // three buttons have just been taken out of the bar.
                  final action = await showDocumentActionsSheet(
                    context,
                    includeView: !_hasRoomForFullToolbar,
                  );
                  if (action == null || !mounted) return;
                  await _runAction(action);
                },
        ),
      if (_mode == _ViewerMode.pages)
        IconButton(
          tooltip: l10n.pagesSplit,
          icon: const Icon(Icons.call_split),
          onPressed: _totalPages == 0 ? null : _splitDocument,
        ),
      // Search stays in the bar at every width. It is the most-used control in
      // a document reader, and burying it behind a sheet to save one slot
      // would be the wrong trade.
      if (_mode == _ViewerMode.read)
        IconButton(
          tooltip: l10n.viewerSearch,
          icon: const Icon(Icons.search),
          onPressed: _searcher == null
              ? null
              : () => setState(() => _searchOpen = !_searchOpen),
        ),
      if (_mode == _ViewerMode.read && _hasRoomForFullToolbar) ...[
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
