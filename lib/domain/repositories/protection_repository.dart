import 'package:folio/domain/models/library_document.dart';

/// Encrypts a document with a password, into a new document.
abstract interface class ProtectionRepository {
  Future<LibraryDocument> protect(int documentId, String password);
}
