import 'package:drift/drift.dart';
import 'package:folio/data/local/app_database.dart';

class SignatureDao {
  SignatureDao(this._db);

  final AppDatabase _db;

  Future<List<Signature>> all() {
    final query = _db.select(_db.signatures)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  Future<int> insert({
    required String label,
    required String strokes,
    required double aspectRatio,
    String kind = 'drawn',
    Uint8List? imageBytes,
  }) => _db
      .into(_db.signatures)
      .insert(
        SignaturesCompanion.insert(
          label: label,
          strokes: strokes,
          aspectRatio: aspectRatio,
          kind: Value(kind),
          imageBytes: Value(imageBytes),
        ),
      );

  Future<void> rename(int id, String label) async {
    await (_db.update(_db.signatures)..where((t) => t.id.equals(id))).write(
      SignaturesCompanion(label: Value(label)),
    );
  }

  Future<void> delete(int id) async {
    await (_db.delete(_db.signatures)..where((t) => t.id.equals(id))).go();
  }
}
