import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/export_repository_impl.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/repositories/export_repository.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late LibraryRepositoryImpl library;
  late ExportRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('export');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = ExportRepositoryImpl(library: library);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<int> seed(String name, String content) async {
    final dir = await Directory.systemTemp.createTemp('src');
    File('${dir.path}/f.pdf').writeAsStringSync(content);
    final doc = await library.importFile(
      '${dir.path}/f.pdf',
      displayName: name,
    );
    return doc.id;
  }

  const plain =
      '%PDF-1.4\ntrailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';
  const encrypted =
      '%PDF-1.4\ntrailer\n<< /Size 9 /Root 1 0 R /Encrypt 8 0 R >>\n'
      'startxref\n9\n%%EOF\n';

  group('prepare', () {
    test('carries the document bytes unchanged', () async {
      final id = await seed('Invoice.pdf', plain);
      final export = await subject.prepare(id);

      expect(String.fromCharCodes(export.bytes), plain);
    });

    // The name is what tells the user which of two similarly named documents
    // they are about to send.
    test('carries the library name', () async {
      final id = await seed('Invoice (redacted).pdf', plain);

      expect((await subject.prepare(id)).displayName, 'Invoice (redacted).pdf');
    });

    test('detects a protected document', () async {
      final id = await seed('Secret.pdf', encrypted);

      expect((await subject.prepare(id)).isProtected, isTrue);
    });

    test('an ordinary document is not protected', () async {
      final id = await seed('Invoice.pdf', plain);

      expect((await subject.prepare(id)).isProtected, isFalse);
    });
  });

  group('refusalFor', () {
    // The OS print renderer needs the password, which Folio does not hold.
    // Refusing is clearer than a job that fails where the user cannot see why.
    test('a protected document cannot be printed', () async {
      final id = await seed('Secret.pdf', encrypted);
      final export = await subject.prepare(id);

      expect(subject.refusalFor(export), PrintRefusal.protected);
    });

    test('an ordinary document can', () async {
      final id = await seed('Invoice.pdf', plain);

      expect(subject.refusalFor(await subject.prepare(id)), isNull);
    });

    // Sharing an encrypted document is perfectly safe - it stays encrypted -
    // so nothing here should stop it.
    test('refusal is about printing only', () async {
      final id = await seed('Secret.pdf', encrypted);
      final export = await subject.prepare(id);

      expect(export.bytes, isNotEmpty, reason: 'still preparable for sharing');
      expect(export.fileName, 'Secret.pdf');
    });
  });
}
