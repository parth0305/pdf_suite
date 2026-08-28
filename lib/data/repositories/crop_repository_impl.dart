import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/crop/page_crop.dart';
import 'package:folio/domain/crop/pdf_crop_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/crop_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

/// Detection renders pages, so a long document would take a visible age. The
/// first pages of a scan are representative, and the union only ever narrows
/// the trim - so sampling can crop too little, never too much.
const _pagesSampled = 12;

/// Rendered detail for detection. Margins land within a point or so at this
/// size, and a 150 dpi A4 raster is four times the pixels for no better answer.
const _detectionDpi = 72.0;

class CropRepositoryImpl implements CropRepository {
  CropRepositoryImpl({
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
  Future<PageMargins> detect(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final handle = await _engine.open(
      FileSource(await _library.resolveReadablePath(doc)),
    );

    try {
      PageMargins? margins;

      final pages = handle.pageCount < _pagesSampled
          ? handle.pageCount
          : _pagesSampled;

      for (var index = 0; index < pages; index++) {
        final info = await _engine.pageInfo(handle, index);
        final visible = TextRect(
          left: 0,
          bottom: 0,
          right: info.widthPt,
          top: info.heightPt,
        );

        final rendered = await _engine.renderPage(
          handle,
          index,
          targetWidthPx: (info.widthPt * _detectionDpi / 72).round(),
          targetHeightPx: (info.heightPt * _detectionDpi / 72).round(),
        );

        final page = detectContentMargins(
          rendered.bgraPixels,
          widthPx: rendered.widthPx,
          heightPx: rendered.heightPx,
          visible: visible,
        );

        // A blank page has no content to trim towards, and its zero margins
        // would zero the whole document's. It is skipped, not unioned.
        if (page.isNothing) continue;
        margins = margins == null ? page : margins.union(page);
      }

      return margins ?? const PageMargins();
    } finally {
      await _engine.close(handle);
    }
  }

  @override
  Future<LibraryDocument> apply(int documentId, PageMargins margins) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    return _documents.store(
      writeCroppedPages(bytes, margins),
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }
}
