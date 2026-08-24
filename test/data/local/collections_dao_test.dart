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
    ref: ManagedRef(relativePath: name, contentHash: name),
    displayName: name,
    sizeBytes: 10,
  );

  group('collections', () {
    test('a new document belongs to no collection', () async {
      await insert('a.pdf');
      expect(await dao.documentsIn(null), hasLength(1));
    });

    test('moving a document places it in the collection', () async {
      final doc = await insert('a.pdf');
      final folder = await dao.createCollection('Invoices');

      await dao.moveDocument(doc, folder);

      expect(await dao.documentsIn(folder), hasLength(1));
      expect(await dao.documentsIn(null), isEmpty);
    });

    test('moving to null returns a document to the root', () async {
      final doc = await insert('a.pdf');
      final folder = await dao.createCollection('Invoices');
      await dao.moveDocument(doc, folder);

      await dao.moveDocument(doc, null);

      expect(await dao.documentsIn(null), hasLength(1));
    });

    test('deleting a collection returns its documents to the root', () async {
      final doc = await insert('a.pdf');
      final folder = await dao.createCollection('Invoices');
      await dao.moveDocument(doc, folder);

      await dao.deleteCollection(folder);

      expect(await dao.allCollections(), isEmpty);
      expect(
        await dao.documentsIn(null),
        hasLength(1),
        reason: 'deleting a folder must never delete documents',
      );
    });

    test('renaming a collection preserves its membership', () async {
      final doc = await insert('a.pdf');
      final folder = await dao.createCollection('Old');
      await dao.moveDocument(doc, folder);

      await dao.renameCollection(folder, 'New');

      expect((await dao.allCollections()).single.name, 'New');
      expect(await dao.documentsIn(folder), hasLength(1));
    });

    test('collections are listed in creation order', () async {
      await dao.createCollection('First');
      await dao.createCollection('Second');
      expect((await dao.allCollections()).map((c) => c.name), [
        'First',
        'Second',
      ]);
    });
  });
}
