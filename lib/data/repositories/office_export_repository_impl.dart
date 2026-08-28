import 'dart:io';

import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/office/docx_writer.dart';
import 'package:folio/domain/office/pptx_writer.dart';
import 'package:folio/domain/office/text_structure.dart';
import 'package:folio/domain/office/xlsx_writer.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/office_export_repository.dart';

class OfficeExportRepositoryImpl implements OfficeExportRepository {
  OfficeExportRepositoryImpl({
    required LibraryRepository library,
    required PdfEngine engine,
  }) : _library = library,
       _engine = engine;

  final LibraryRepository _library;
  final PdfEngine _engine;

  @override
  Future<bool> hasText(int documentId) async {
    final handle = await _open(documentId);

    try {
      for (var index = 0; index < handle.pageCount; index++) {
        final text = await _engine.extractText(handle, index);
        if (text != null && text.fullText.trim().isNotEmpty) return true;
      }
      return false;
    } finally {
      await _engine.close(handle);
    }
  }

  @override
  Future<ExportedOfficeFile> export(int documentId, OfficeFormat format) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final handle = await _open(documentId);
    final pages = <OfficePage>[];
    final lines = <List<TextLine>>[];

    try {
      for (var index = 0; index < handle.pageCount; index++) {
        final info = await _engine.pageInfo(handle, index);
        final text = await _engine.extractText(handle, index);
        final pageLines = text == null ? <TextLine>[] : linesOf(text);

        lines.add(pageLines);
        pages.add(
          OfficePage(
            paragraphs: paragraphsOf(pageLines),
            size: TextRect(
              left: 0,
              bottom: 0,
              right: info.widthPt,
              top: info.heightPt,
            ),
          ),
        );
      }
    } finally {
      await _engine.close(handle);
    }

    final bytes = switch (format) {
      OfficeFormat.word => writeDocx(pages),
      OfficeFormat.powerPoint => writePptx(pages),
      OfficeFormat.excel => writeXlsx([
        for (var index = 0; index < lines.length; index++)
          OfficeSheet(
            name: 'Page ${index + 1}',
            rows: [
              for (final line in lines[index])
                cellsOf(line, columnGap: columnGapFor(lines[index])),
            ],
          ),
      ]),
    };

    // A temporary directory, not the library: these are files on their way
    // out, not documents Folio can open again.
    final directory = await Directory.systemTemp.createTemp('folio_office');
    final name = officeName(doc, format);
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);

    return ExportedOfficeFile(path: file.path, name: name);
  }

  Future<PdfDocumentHandle> _open(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    return _engine.open(FileSource(await _library.resolveReadablePath(doc)));
  }
}
