import 'package:folio/domain/archive/pdfa_check.dart';
import 'package:folio/domain/models/library_document.dart';

/// Converts documents to PDF/A, and says when it cannot.
abstract interface class ArchiveRepository {
  Future<PdfaReport> check(int documentId);

  Future<LibraryDocument> convert(int documentId);
}
