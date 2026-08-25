import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/domain/models/document_ref.dart';

void main() {
  late AppDatabase db;
  late LibraryDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = LibraryDao(db);
  });

  tearDown(() => db.close());

  Future<int> insert(String name) => dao.insertDocument(
    ref: ManagedRef(relativePath: name, contentHash: 'hash-$name'),
    displayName: name,
    sizeBytes: 1024,
  );

  group('LibraryDao', () {
    test('inserts and reads back a document', () async {
      final id = await insert('invoice.pdf');
      final all = await dao.allDocuments();

      expect(all, hasLength(1));
      expect(all.single.id, id);
      expect(all.single.displayName, 'invoice.pdf');
      expect(all.single.ref, isA<ManagedRef>());
    });

    test('recents are ordered by most recently opened', () async {
      final a = await insert('a.pdf');
      final b = await insert('b.pdf');

      await dao.markOpened(a, at: DateTime(2026, 8, 1));
      await dao.markOpened(b, at: DateTime(2026, 8, 2));

      final recents = await dao.recents();
      expect(recents.first.id, b, reason: 'b was opened last');
    });

    test('never-opened documents are excluded from recents', () async {
      await insert('never.pdf');
      expect(await dao.recents(), isEmpty);
    });

    test('favorites returns only favourited documents', () async {
      final a = await insert('a.pdf');
      await insert('b.pdf');
      await dao.setFavorite(a, true);

      final favs = await dao.favorites();
      expect(favs, hasLength(1));
      expect(favs.single.id, a);
    });

    test('rename changes the display name and nothing else', () async {
      final id = await insert('old.pdf');
      await dao.rename(id, 'new.pdf');

      final doc = (await dao.allDocuments()).single;
      expect(doc.displayName, 'new.pdf');
      expect(doc.sizeBytes, 1024);
    });

    test('delete removes the row', () async {
      final id = await insert('gone.pdf');
      await dao.deleteDocument(id);
      expect(await dao.allDocuments(), isEmpty);
    });

    test('recents respects the limit', () async {
      for (var i = 0; i < 5; i++) {
        final id = await insert('doc$i.pdf');
        await dao.markOpened(
          id,
          at: DateTime(2026, 8, 1).add(Duration(days: i)),
        );
      }
      expect(await dao.recents(limit: 3), hasLength(3));
    });
  });
}
