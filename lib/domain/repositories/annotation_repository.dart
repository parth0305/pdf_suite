import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/models/library_document.dart';

/// Saves staged annotations into a new document.
///
/// Like page operations, this never modifies its source.
abstract interface class AnnotationRepository {
  Future<LibraryDocument> saveAnnotations({
    required int sourceDocumentId,
    required List<Annotation> annotations,
  });
}
