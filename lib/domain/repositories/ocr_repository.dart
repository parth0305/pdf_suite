import 'package:folio/domain/models/library_document.dart';

/// Adds a searchable text layer to a document, into a new document.
abstract interface class OcrRepository {
  Future<LibraryDocument> recognise(int documentId);
}
