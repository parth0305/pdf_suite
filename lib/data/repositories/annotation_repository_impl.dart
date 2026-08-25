import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/annotations/pdf_annotation_writer.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/annotation_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class AnnotationRepositoryImpl implements AnnotationRepository {
  const AnnotationRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<LibraryDocument> saveMarkup({
    required int sourceDocumentId,
    required List<TextMarkup> markups,
  }) async {
    if (markups.isEmpty) {
      throw ArgumentError.value(markups, 'markups', 'nothing to save');
    }

    final source = (await _library.all()).firstWhere(
      (d) => d.id == sourceDocumentId,
    );
    final bytes = await File(
      await _library.resolveReadablePath(source),
    ).readAsBytes();

    // Read metadata from the source: writeMarkup appends to the document, and
    // going through DocumentWriter re-attaches it on the way out.
    final metadata = PdfMetadata.readFrom(bytes);
    final annotated = writeMarkup(bytes, markups);

    return _documents.store(
      annotated,
      editedName(source.displayName),
      metadata: metadata,
    );
  }
}
