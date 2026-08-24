import 'package:drift/drift.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';

class LibraryDao {
  LibraryDao(this._db);

  final AppDatabase _db;

  Future<int> insertDocument({
    required DocumentRef ref,
    required String displayName,
    required int sizeBytes,
    int? pageCount,
  }) {
    return _db
        .into(_db.documents)
        .insert(
          DocumentsCompanion.insert(
            refPayload: ref.encode(),
            displayName: displayName,
            sizeBytes: sizeBytes,
            pageCount: Value(pageCount),
          ),
        );
  }

  Future<List<LibraryDocument>> allDocuments() async {
    final rows = await _db.select(_db.documents).get();
    return rows.map(_toDomain).toList();
  }

  Future<List<LibraryDocument>> recents({int limit = 20}) async {
    final query = _db.select(_db.documents)
      ..where((t) => t.lastOpenedAt.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.lastOpenedAt)])
      ..limit(limit);
    return (await query.get()).map(_toDomain).toList();
  }

  Future<List<LibraryDocument>> favorites() async {
    final query = _db.select(_db.documents)
      ..where((t) => t.isFavorite.equals(true));
    return (await query.get()).map(_toDomain).toList();
  }

  /// [at] is injectable so ordering tests are deterministic rather than
  /// depending on wall-clock resolution.
  Future<void> markOpened(int id, {DateTime? at}) async {
    await (_db.update(_db.documents)..where((t) => t.id.equals(id))).write(
      DocumentsCompanion(lastOpenedAt: Value(at ?? DateTime.now())),
    );
  }

  Future<void> setFavorite(int id, bool value) async {
    await (_db.update(_db.documents)..where((t) => t.id.equals(id))).write(
      DocumentsCompanion(isFavorite: Value(value)),
    );
  }

  Future<void> rename(int id, String name) async {
    await (_db.update(_db.documents)..where((t) => t.id.equals(id))).write(
      DocumentsCompanion(displayName: Value(name)),
    );
  }

  Future<void> deleteDocument(int id) async {
    await (_db.delete(_db.documents)..where((t) => t.id.equals(id))).go();
  }

  LibraryDocument _toDomain(Document row) => LibraryDocument(
    id: row.id,
    ref: DocumentRef.decode(row.refPayload),
    displayName: row.displayName,
    sizeBytes: row.sizeBytes,
    addedAt: row.addedAt,
    lastOpenedAt: row.lastOpenedAt,
    isFavorite: row.isFavorite,
    pageCount: row.pageCount,
  );
}
