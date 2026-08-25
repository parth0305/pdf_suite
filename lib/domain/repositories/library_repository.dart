import 'package:folio/domain/models/library_collection.dart';
import 'package:folio/domain/models/library_document.dart';

abstract interface class LibraryRepository {
  Future<LibraryDocument> importFile(
    String sourcePath, {
    required String displayName,
  });
  Future<LibraryDocument> openInPlace(
    String pathOrUri, {
    required String displayName,
  });
  Future<List<LibraryDocument>> all();
  Future<List<LibraryDocument>> recents({int limit = 20});
  Future<List<LibraryDocument>> favorites();
  Future<String> resolveReadablePath(LibraryDocument doc);
  Future<void> markOpened(int id);
  Future<void> setFavorite(int id, bool value);
  Future<void> rename(int id, String name);
  Future<void> delete(int id);
  Future<LibraryDocument> duplicate(int id);

  /// Copies a document out to a user-chosen location. Exports, never moves:
  /// the library copy is left untouched.
  Future<void> exportCopy(int docId, String destinationPath);

  /// Folders are virtual; null returns the document to the library root.
  Future<void> moveToCollection(int docId, int? collectionId);

  Future<List<LibraryCollection>> collections();
  Future<int> createCollection(String name);
  Future<void> renameCollection(int id, String name);

  /// Deleting a collection returns its documents to the library root. It never
  /// deletes documents.
  Future<void> deleteCollection(int id);

  /// Registers a file already written into the library root. Used by page
  /// operations, which produce bytes rather than importing an external file.
  Future<LibraryDocument> registerManaged({
    required String relativePath,
    required String contentHash,
    required String displayName,
    required int sizeBytes,
  });
}
