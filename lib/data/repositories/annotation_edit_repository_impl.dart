import 'dart:convert';
import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/annotation_edit_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class AnnotationEditRepositoryImpl implements AnnotationEditRepository {
  AnnotationEditRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  Future<LibraryDocument> _find(int id) async =>
      (await _library.all()).firstWhere((d) => d.id == id);

  @override
  Future<List<SavedAnnotation>> load(int documentId) async {
    final doc = await _find(documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    // `all`, not a loop over pageCount: pageCount is nullable, and iterating
    // until a page comes back empty would stop at the first unannotated page.
    return PdfAnnotationReader.parse(
      latin1.decode(bytes, allowInvalid: true),
    ).all;
  }

  @override
  Future<LibraryDocument> save({
    required int documentId,
    required Set<int> deleted,
    required Map<int, AnnotationStyle> restyled,
    required Map<int, TextRect> moved,
  }) async {
    if (deleted.isEmpty && restyled.isEmpty && moved.isEmpty) {
      throw ArgumentError('nothing to save');
    }

    final doc = await _find(documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    final edited = applyAnnotationEdits(
      bytes,
      deleted: deleted,
      restyled: restyled,
      moved: moved,
    );

    if (doc.createdByFolio && doc.isManaged) {
      return _library.replaceManagedContent(
        documentId: documentId,
        bytes: edited,
      );
    }

    // Imported: never rewritten. Metadata is re-read from the source so the
    // new document inherits it, exactly as the annotation writer does.
    return _documents.store(
      edited,
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }
}
