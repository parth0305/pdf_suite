import 'package:folio/domain/models/library_document.dart';

/// Paints annotations into the pages, into a new document.
abstract interface class FlattenRepository {
  Future<LibraryDocument> apply(int documentId);
}
