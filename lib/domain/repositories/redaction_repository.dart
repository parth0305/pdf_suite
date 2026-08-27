import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/redaction/redaction_box.dart';

/// Removes the content under each box, into a new document.
abstract interface class RedactionRepository {
  Future<LibraryDocument> apply(int documentId, List<RedactionBox> boxes);
}
