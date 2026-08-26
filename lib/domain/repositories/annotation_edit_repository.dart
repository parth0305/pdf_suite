import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';

/// Loads annotations already saved in a document, and writes edits back.
abstract interface class AnnotationEditRepository {
  Future<List<SavedAnnotation>> load(int documentId);

  /// Folio-created documents are rewritten in place; imported documents
  /// produce a new document, leaving the imported copy untouched.
  Future<LibraryDocument> save({
    required int documentId,
    required Set<int> deleted,
    required Map<int, AnnotationStyle> restyled,
    required Map<int, TextRect> moved,
  });
}
