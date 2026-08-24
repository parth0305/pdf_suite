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
}
