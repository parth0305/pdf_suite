import 'dart:io';

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
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<LibraryDocument> apply(int documentId, PageNumbering numbering) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    final out = writePageNumbers(bytes, numbering);

    return _documents.store(
      out,
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }
}
