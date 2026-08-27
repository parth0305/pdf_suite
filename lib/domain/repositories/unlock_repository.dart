import 'package:folio/domain/models/library_document.dart';

/// Removes password protection, into a new document.
abstract interface class UnlockRepository {
  /// Throws `WrongPassword` when the password does not open the document, and
  /// `UnsupportedPdfStructure` when it is not protected at all.
  Future<LibraryDocument> unlock(int documentId, String password);
}
