import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';

/// Reads and edits a document's title, author, subject and keywords.
abstract interface class MetadataRepository {
  Future<PdfMetadata> read(int documentId);

  /// Writes [metadata], into a new document.
  Future<LibraryDocument> save(int documentId, PdfMetadata metadata);
}
