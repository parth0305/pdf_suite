import 'package:folio/domain/forms/form_field.dart';
import 'package:folio/domain/models/library_document.dart';

/// Reads and fills a document's AcroForm.
abstract interface class FormRepository {
  Future<List<FormField>> fields(int documentId);

  /// Fills [values], keyed by fully qualified field name, into a new document.
  Future<LibraryDocument> fill(int documentId, Map<String, String?> values);
}
