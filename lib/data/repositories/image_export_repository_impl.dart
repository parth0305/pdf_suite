import 'dart:io';

import 'package:folio/data/signature/signature_photo_source.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/export/page_selection.dart';
import 'package:folio/domain/repositories/image_export_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';

class ImageExportRepositoryImpl implements ImageExportRepository {
  ImageExportRepositoryImpl({
    required LibraryRepository library,
    required PdfEngine engine,
  }) : _library = library,
       _engine = engine;

  final LibraryRepository _library;
  final PdfEngine _engine;

  @override
  Future<List<ExportedPage>> export({
    required int documentId,
    required String range,
    required int dpi,
  }) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final path = await _library.resolveReadablePath(doc);

    // A temporary directory, not the library: these are images on their way
    // out, not documents.
    final out = await Directory.systemTemp.createTemp('folio_pages');
    final handle = await _engine.open(FileSource(path));
    final exported = <ExportedPage>[];

    try {
      final pages = parsePageRange(range, pageCount: handle.pageCount);

      for (final index in pages) {
        final info = await _engine.pageInfo(handle, index);
        final rendered = await _engine.renderPage(
          handle,
          index,
          targetWidthPx: (info.widthPt * dpi / 72).round(),
          targetHeightPx: (info.heightPt * dpi / 72).round(),
        );

        final png = await encodeRgbaToPng(
          bgraToRgba(rendered.bgraPixels),
          rendered.widthPx,
          rendered.heightPx,
        );

        final name = pageImageName(
          doc.displayName,
          index + 1,
          handle.pageCount,
        );
        final file = File('${out.path}/$name')..writeAsBytesSync(png);

        exported.add(ExportedPage(path: file.path, pageNumber: index + 1));
      }
    } finally {
      await _engine.close(handle);
    }

    return exported;
  }
}
