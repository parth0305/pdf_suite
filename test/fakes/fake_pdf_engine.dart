import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';

class _FakeDoc {
  _FakeDoc(this.pages, this.password, this.outline);
  final List<String> pages;
  final String? password;
  final List<OutlineNode> outline;
}

/// In-memory [PdfEngine] for unit tests.
///
/// Exists so that domain and data tests run on CI runners with no simulator,
/// which is what makes the 80% coverage target reachable.
class FakePdfEngine implements PdfEngine {
  final Map<String, _FakeDoc> _docs = {};
  final Map<String, String> _openHandles = {};
  int _nextHandle = 0;

  void addDocument(
    String name, {
    required List<String> pages,
    String? password,
    List<OutlineNode> outline = const [],
  }) {
    _docs[name] = _FakeDoc(pages, password, outline);
  }

  String _nameOf(DocumentBytesSource source) => switch (source) {
    FileSource(:final path) => path,
    BytesSource(:final sourceName) => sourceName,
  };

  @override
  Future<PdfDocumentHandle> open(
    DocumentBytesSource source, {
    PasswordCallback? onPasswordRequired,
  }) async {
    final name = _nameOf(source);
    final doc = _docs[name];
    if (doc == null) {
      throw const DocumentCorrupt(technicalDetail: 'fake: no such document');
    }

    if (doc.password != null) {
      final supplied = await onPasswordRequired?.call();
      if (supplied == null) {
        throw const PasswordRequired(technicalDetail: 'fake: open cancelled');
      }
      if (supplied != doc.password) {
        throw const WrongPassword(technicalDetail: 'fake: password mismatch');
      }
    }

    final id = 'fake-${_nextHandle++}';
    _openHandles[id] = name;
    return PdfDocumentHandle(id: id, pageCount: doc.pages.length);
  }

  _FakeDoc _resolve(PdfDocumentHandle handle) {
    final name = _openHandles[handle.id];
    final doc = name == null ? null : _docs[name];
    if (doc == null) {
      throw const UnknownFailure(
        technicalDetail: 'fake: handle closed or invalid',
      );
    }
    return doc;
  }

  @override
  Future<PdfPageInfo> pageInfo(PdfDocumentHandle doc, int pageIndex) async {
    _resolve(doc);
    return PdfPageInfo(
      index: pageIndex,
      widthPt: 595,
      heightPt: 842,
      rotationQuarterTurns: 0,
    );
  }

  @override
  Future<RenderedPage> renderPage(
    PdfDocumentHandle doc,
    int pageIndex, {
    required int targetWidthPx,
    required int targetHeightPx,
  }) async {
    _resolve(doc);
    return RenderedPage(
      widthPx: targetWidthPx,
      heightPx: targetHeightPx,
      bgraPixels: Uint8List(targetWidthPx * targetHeightPx * 4),
    );
  }

  @override
  Future<PageText?> extractText(PdfDocumentHandle doc, int pageIndex) async {
    final d = _resolve(doc);
    final text = d.pages[pageIndex];
    // One rect per code unit, laid out left to right, mirroring the alignment
    // guarantee documented on PageText.
    return PageText(
      fullText: text,
      charRects: [
        for (var i = 0; i < text.length; i++)
          TextRect(left: i * 7.0, top: 800, right: i * 7.0 + 7, bottom: 788),
      ],
    );
  }

  @override
  Future<List<OutlineNode>> outline(PdfDocumentHandle doc) async =>
      _resolve(doc).outline;

  @override
  Future<DocumentPermissions?> permissions(PdfDocumentHandle doc) async {
    _resolve(doc);
    return const DocumentPermissions(
      allowsCopying: true,
      allowsPrinting: true,
      allowsDocumentAssembly: true,
      allowsModifyAnnotations: true,
      securityHandlerRevision: 0,
    );
  }

  @override
  Future<void> close(PdfDocumentHandle doc) async {
    _openHandles.remove(doc.id);
  }
}
