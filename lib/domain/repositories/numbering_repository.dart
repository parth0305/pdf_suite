import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/numbering/page_numbers.dart';

/// Stamps page numbers, into a new document.
abstract interface class NumberingRepository {
  Future<LibraryDocument> apply(int documentId, PageNumbering numbering);
}
