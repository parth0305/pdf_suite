import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:folio/data/ocr/ocr_engine.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/ocr/ocr_text_layer.dart';
import 'package:folio/domain/ocr/pdf_ocr_writer.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/ocr_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

/// Pixels per inch each page is rendered at before recognition.
///
/// Tesseract's accuracy falls off sharply below roughly 200 DPI, and above
/// 300 the extra pixels buy little but time.
const ocrDpi = 200;

class OcrRepositoryImpl implements OcrRepository {
  OcrRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
    required PdfEngine engine,
    required OcrEngine ocr,
  }) : _library = library,
       _documents = documents,
       _engine = engine,
       _ocr = ocr;

  final LibraryRepository _library;
  final DocumentWriter _documents;
  final PdfEngine _engine;
  final OcrEngine _ocr;

  @override
  Future<LibraryDocument> recognise(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final path = await _library.resolveReadablePath(doc);
    final bytes = await File(path).readAsBytes();

    final scratch = await Directory.systemTemp.createTemp('ocr');
    final handle = await _engine.open(FileSource(path));
    final layers = <int, String>{};

    try {
      for (var i = 0; i < handle.pageCount; i++) {
        layers[i] = await _layerFor(handle, i, scratch);
      }
    } finally {
      await _engine.close(handle);
      if (scratch.existsSync()) await scratch.delete(recursive: true);
    }

    // Throws ArgumentError when nothing was recognised anywhere, rather than
    // producing a duplicate document with no text in it.
    final recognised = writeOcrLayer(bytes, layers);

    return _documents.store(
      recognised,
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }

  Future<String> _layerFor(
    PdfDocumentHandle handle,
    int index,
    Directory scratch,
  ) async {
    final info = await _engine.pageInfo(handle, index);
    final width = (info.widthPt * ocrDpi / 72).round();
    final height = (info.heightPt * ocrDpi / 72).round();

    final rendered = await _engine.renderPage(
      handle,
      index,
      targetWidthPx: width,
      targetHeightPx: height,
    );

    final file = File('${scratch.path}/page_$index.png')
      ..writeAsBytesSync(await _png(rendered));

    final page = await _ocr.recognise(file.path);

    // The render covers the whole page, so the image maps onto it one to one
    // and there is no offset to account for.
    return ocrTextLayer(
      page: page,
      imageWidth: rendered.widthPx,
      imageHeight: rendered.heightPx,
      pageWidth: info.widthPt,
      pageHeight: info.heightPt,
      offsetX: 0,
      offsetY: 0,
    );
  }

  /// BGRA to PNG through dart:ui, so no image encoder is needed.
  Future<Uint8List> _png(RenderedPage page) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(page.bgraPixels),
      page.widthPx,
      page.heightPx,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );

    final image = await completer.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return data!.buffer.asUint8List();
  }
}
