import 'dart:io';

import 'package:folio/data/fonts/font_assets.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/numbering/page_numbers.dart';
import 'package:folio/domain/numbering/pdf_page_number_writer.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/numbering_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class NumberingRepositoryImpl implements NumberingRepository {
  NumberingRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
    FontAssets? fonts,
  }) : _library = library,
       _documents = documents,
       _fonts = fonts;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  /// Absent in tests that have no asset bundle. Without it the numbers are
  /// still drawn, against whatever encoding the reader assumes.
  final FontAssets? _fonts;

  @override
  Future<LibraryDocument> apply(int documentId, PageNumbering numbering) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    final out = writePageNumbers(bytes, numbering, font: await _fonts?.text());

    return _documents.store(
      out,
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }
}
