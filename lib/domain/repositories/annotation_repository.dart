import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/models/library_document.dart';

/// Saves staged markup into a new document.
///
/// Like page operations, this never modifies its source.
abstract interface class AnnotationRepository {
  Future<LibraryDocument> saveMarkup({
    required int sourceDocumentId,
    required List<TextMarkup> markups,
  });
}
