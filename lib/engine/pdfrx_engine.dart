import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/engine/pdfrx_mappers.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

/// [PdfEngine] backed by pdfrx / PDFium.
///
/// Translates every pdfrx exception into an [AppFailure] so that raw platform
/// errors never escape the data layer.
class PdfrxEngine implements PdfEngine {
  final Map<String, rx.PdfDocument> _open = {};
  int _nextHandle = 0;

  @override
  Future<PdfDocumentHandle> open(
    DocumentBytesSource source, {
    PasswordCallback? onPasswordRequired,
  }) async {
    var attempts = 0;

    // pdfrx calls this repeatedly until it returns null or a valid password,
    // so a wrong password naturally produces a re-prompt rather than an error.
    // The exception only arrives once the user gives up by returning null.
    Future<String?> provider() async {
      attempts++;
      return onPasswordRequired?.call();
    }

    try {
      final doc = switch (source) {
        FileSource(:final path) => await rx.PdfDocument.openFile(
          path,
          passwordProvider: provider,
        ),
        BytesSource(:final bytes, :final sourceName) =>
          await rx.PdfDocument.openData(
            bytes,
            sourceName: sourceName,
            passwordProvider: provider,
          ),
      };

      final id = 'pdfrx-${_nextHandle++}';
      _open[id] = doc;
      return PdfDocumentHandle(
        id: id,
        pageCount: doc.pages.length,
        permissionBits: doc.permissions?.permissions,
      );
    } on rx.PdfPasswordException catch (e) {
      // Because pdfrx loops, reaching here means the user cancelled. One prompt
      // means they simply declined; more than one means at least one supplied
      // password was rejected before they gave up.
      throw attempts > 1
          ? WrongPassword(technicalDetail: e.toString())
          : PasswordRequired(technicalDetail: e.toString());
    } on rx.PdfException catch (e) {
      throw DocumentCorrupt(technicalDetail: e.toString());
    } catch (e) {
      throw UnknownFailure(technicalDetail: e.toString());
    }
  }

  rx.PdfDocument _resolve(PdfDocumentHandle handle) {
    final doc = _open[handle.id];
    if (doc == null) {
      throw const UnknownFailure(technicalDetail: 'handle closed or invalid');
    }
    return doc;
  }

  /// Internal access for [PdfrxPageEditor]. Not part of [PdfEngine]: exposing
  /// it there would give every reader a route to the write path.
  rx.PdfDocument documentFor(PdfDocumentHandle handle) => _resolve(handle);

  @override
  Future<PdfPageInfo> pageInfo(PdfDocumentHandle doc, int pageIndex) async {
    final page = _resolve(doc).pages[pageIndex];
    return PdfPageInfo(
      index: pageIndex,
      widthPt: page.width,
      heightPt: page.height,
      rotationQuarterTurns: page.rotation.index,
    );
  }

  @override
  Future<RenderedPage> renderPage(
    PdfDocumentHandle doc,
    int pageIndex, {
    required int targetWidthPx,
    required int targetHeightPx,
  }) async {
    final page = _resolve(doc).pages[pageIndex];
    final image = await page.render(
      fullWidth: targetWidthPx.toDouble(),
      fullHeight: targetHeightPx.toDouble(),
    );
    if (image == null) {
      throw const UnsupportedFeature(technicalDetail: 'render returned null');
    }
    try {
      return RenderedPage(
        widthPx: image.width,
        heightPx: image.height,
        // Copy before dispose: image.pixels is backed by native memory that
        // becomes invalid the moment dispose() is called.
        bgraPixels: Uint8List.fromList(image.pixels),
      );
    } finally {
      image.dispose();
    }
  }

  @override
  Future<PageText?> extractText(PdfDocumentHandle doc, int pageIndex) async {
    final raw = await _resolve(doc).pages[pageIndex].loadText();
    if (raw == null) return null;
    return PageText(
      fullText: raw.fullText,
      charRects: [
        for (final r in raw.charRects)
          TextRect(left: r.left, top: r.top, right: r.right, bottom: r.bottom),
      ],
    );
  }

  @override
  Future<List<OutlineNode>> outline(PdfDocumentHandle doc) async {
    final nodes = await _resolve(doc).loadOutline();
    return nodes.map(convertOutlineNode).toList();
  }

  @override
  Future<DocumentPermissions?> permissions(PdfDocumentHandle doc) async {
    final p = _resolve(doc).permissions;
    if (p == null) return null;
    return DocumentPermissions(
      allowsCopying: p.allowsCopying,
      allowsPrinting: p.allowsPrinting,
      allowsDocumentAssembly: p.allowsDocumentAssembly,
      allowsModifyAnnotations: p.allowsModifyAnnotations,
      securityHandlerRevision: p.securityHandlerRevision,
    );
  }

  @override
  Future<void> close(PdfDocumentHandle doc) async {
    await _open.remove(doc.id)?.dispose();
  }
}
