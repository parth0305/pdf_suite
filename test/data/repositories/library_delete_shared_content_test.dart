import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late LibraryRepositoryImpl library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dupdel');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  // Storage is content-addressed, so importing the same file twice produces
  // two library rows pointing at ONE file. Deleting either must not take the
  // other's content with it.
  test(
    'deleting one of two identical imports leaves the other readable',
    () async {
      final source = Directory.systemTemp.createTempSync('src');
      const bytes = '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n';
      File('${source.path}/a.pdf').writeAsStringSync(bytes);
      File('${source.path}/b.pdf').writeAsStringSync(bytes);

      final first = await library.importFile(
        '${source.path}/a.pdf',
        displayName: 'First.pdf',
      );
      final second = await library.importFile(
        '${source.path}/b.pdf',
        displayName: 'Second.pdf',
      );

      await library.delete(first.id);

      expect(
        await File(await library.resolveReadablePath(second)).readAsString(),
        bytes,
        reason: 'the surviving row must still resolve to its content',
      );
    },
  );

  // The guard must not go the other way: a document nothing else references
  // has to be removed, or deleting never frees any space.
  test('deleting the only row still removes its file', () async {
    final source = Directory.systemTemp.createTempSync('src');
    File('${source.path}/a.pdf').writeAsStringSync('%PDF-1.4\n%%EOF\n');

    final doc = await library.importFile(
      '${source.path}/a.pdf',
      displayName: 'Only.pdf',
    );
    final path = await library.resolveReadablePath(doc);

    await library.delete(doc.id);

    expect(File(path).existsSync(), isFalse);
  });

  test('deleting both eventually removes the file', () async {
    final source = Directory.systemTemp.createTempSync('src');
    const bytes = '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n';
    File('${source.path}/a.pdf').writeAsStringSync(bytes);
    File('${source.path}/b.pdf').writeAsStringSync(bytes);

    final first = await library.importFile(
      '${source.path}/a.pdf',
      displayName: 'First.pdf',
    );
    final second = await library.importFile(
      '${source.path}/b.pdf',
      displayName: 'Second.pdf',
    );
    final path = await library.resolveReadablePath(second);

    await library.delete(first.id);
    expect(File(path).existsSync(), isTrue, reason: 'one row still needs it');

    await library.delete(second.id);
    expect(File(path).existsSync(), isFalse, reason: 'now nothing does');
  });
}
