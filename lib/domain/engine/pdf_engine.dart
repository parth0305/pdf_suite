import 'dart:typed_data';

import 'package:folio/domain/engine/pdf_types.dart';

/// Supplies a password when an encrypted document is opened. Returning null
/// cancels the open.
///
/// Implementations may call this **repeatedly**: a rejected password results in
/// another call rather than an immediate failure, which is what produces the
/// re-prompt behaviour in the UI. A failure is only raised once the callback
/// returns null. Consequently `WrongPassword` means "at least one password was
/// rejected before the user gave up", while `PasswordRequired` means "the user
/// declined without trying".
typedef PasswordCallback = Future<String?> Function();

/// Where a document's bytes come from.
sealed class DocumentBytesSource {
  const DocumentBytesSource();
}

final class FileSource extends DocumentBytesSource {
  const FileSource(this.path);
  final String path;
}

final class BytesSource extends DocumentBytesSource {
  const BytesSource(this.bytes, {required this.sourceName});
  final Uint8List bytes;
  final String sourceName;
}

/// Read-only access to PDF documents.
///
/// There is intentionally **no write, save, or export method**. SP-1 ships a
/// reader; document mutation arrives in SP-2 behind a separate interface. Adding
/// a write method here would silently remove the guarantee that SP-1 cannot
/// corrupt a user's file.
///
/// Implementations must throw `AppFailure` subtypes, never raw platform
/// exceptions.
abstract interface class PdfEngine {
  Future<PdfDocumentHandle> open(
    DocumentBytesSource source, {
    PasswordCallback? onPasswordRequired,
  });

  Future<PdfPageInfo> pageInfo(PdfDocumentHandle doc, int pageIndex);

  Future<RenderedPage> renderPage(
    PdfDocumentHandle doc,
    int pageIndex, {
    required int targetWidthPx,
    required int targetHeightPx,
  });

  Future<PageText?> extractText(PdfDocumentHandle doc, int pageIndex);

  Future<List<OutlineNode>> outline(PdfDocumentHandle doc);

  Future<DocumentPermissions?> permissions(PdfDocumentHandle doc);

  Future<void> close(PdfDocumentHandle doc);
}
