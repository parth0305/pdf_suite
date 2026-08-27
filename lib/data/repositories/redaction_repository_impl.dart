import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/redaction/pdf_redaction_writer.dart';
import 'package:folio/domain/redaction/redacted_text_layer.dart';
import 'package:folio/domain/redaction/redaction_box.dart';
import 'package:folio/domain/redaction/redaction_raster.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/redaction_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class RedactionRepositoryImpl implements RedactionRepository {
  RedactionRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
    required PdfEngine engine,
  }) : _library = library,
       _documents = documents,
       _engine = engine;

  final LibraryRepository _library;
  final DocumentWriter _documents;
  final PdfEngine _engine;

  @override
  Future<LibraryDocument> apply(
    int documentId,
    List<RedactionBox> boxes,
  ) async {
    if (boxes.isEmpty) {
      throw ArgumentError.value(boxes, 'boxes', 'nothing to redact');
    }

    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final path = await _library.resolveReadablePath(doc);
    final bytes = await File(path).readAsBytes();

    final handle = await _engine.open(FileSource(path));
    final pages = <int, RedactedPage>{};

    try {
      for (final index in boxes.map((b) => b.pageIndex).toSet()) {
        pages[index] = await _rasterise(handle, index, boxes);
      }
    } finally {
      await _engine.close(handle);
    }

    final redacted = writeRedacted(original: bytes, pages: pages);

    // Metadata is carried through as every other write path does. It is NOT
    // redacted: a name in /Title survives, which the confirmation dialog says
    // out loud rather than leaving someone to discover it.
    return _documents.store(
      redacted,
      redactedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }

  Future<RedactedPage> _rasterise(
    PdfDocumentHandle handle,
    int index,
    List<RedactionBox> boxes,
  ) async {
    final info = await _engine.pageInfo(handle, index);
    final mediaBox = TextRect(
      left: 0,
      right: info.widthPt,
      top: info.heightPt,
      bottom: 0,
    );
    final size = rasterSizeFor(mediaBox);

    final rendered = await _engine.renderPage(
      handle,
      index,
      targetWidthPx: size.width,
      targetHeightPx: size.height,
    );

    final painted = paintBoxes(
      bgra: rendered.bgraPixels,
      widthPx: rendered.widthPx,
      heightPx: rendered.heightPx,
      mediaBox: mediaBox,
      boxes: boxes,
      pageIndex: index,
    );

    final text = await _engine.extractText(handle, index);

    return RedactedPage(
      widthPx: rendered.widthPx,
      heightPx: rendered.heightPx,
      rgb: bgraToRgb(painted),
      invisibleText: text == null
          ? ''
          : invisibleTextStream(text, survivingIndices(text, boxes, index)),
    );
  }
}
