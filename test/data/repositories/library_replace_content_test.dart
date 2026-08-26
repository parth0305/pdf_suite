import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late DocumentWriter writer;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('replace');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    writer = DocumentWriter(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

  test('a document Folio writes is marked as Folio-created', () async {
    final doc = await writer.store(bytes('%PDF-1.4 one'), 'One.pdf');
    expect(doc.createdByFolio, isTrue);
  });

  test('an imported document is not marked as Folio-created', () async {
    final f = File('${root.path}/outside.pdf')
      ..writeAsBytesSync(bytes('%PDF-1.4 outside'));
    final doc = await library.importFile(f.path, displayName: 'Outside.pdf');

    expect(doc.createdByFolio, isFalse);
  });

  test('replacing content keeps the same library row', () async {
    final doc = await writer.store(bytes('%PDF-1.4 one'), 'One.pdf');

    final updated = await library.replaceManagedContent(
      documentId: doc.id,
      bytes: bytes('%PDF-1.4 one edited'),
    );

    expect(updated.id, doc.id);
    expect(updated.displayName, 'One.pdf');
    expect(await library.all(), hasLength(1));
  });

  test('replacing content writes the new bytes', () async {
    final doc = await writer.store(bytes('%PDF-1.4 one'), 'One.pdf');

    final updated = await library.replaceManagedContent(
      documentId: doc.id,
      bytes: bytes('%PDF-1.4 one edited'),
    );

    final onDisk = latin1.decode(
      await File(await library.resolveReadablePath(updated)).readAsBytes(),
      allowInvalid: true,
    );
    expect(onDisk, '%PDF-1.4 one edited');
  });

  // Storage is content-addressed, so new bytes live at a new path. The old
  // file must not be left behind.
  test('the superseded file is removed', () async {
    final doc = await writer.store(bytes('%PDF-1.4 one'), 'One.pdf');
    final oldPath = await library.resolveReadablePath(doc);

    await library.replaceManagedContent(
      documentId: doc.id,
      bytes: bytes('%PDF-1.4 one edited'),
    );

    expect(File(oldPath).existsSync(), isFalse);
  });

  // Content-addressed storage means two identical documents share one file.
  // Removing it on behalf of one would break the other.
  test('a file another row still references is kept', () async {
    final first = await writer.store(bytes('%PDF-1.4 same'), 'First.pdf');
    final second = await writer.store(bytes('%PDF-1.4 same'), 'Second.pdf');
    expect(
      await library.resolveReadablePath(first),
      await library.resolveReadablePath(second),
      reason: 'identical content is stored once',
    );
    final shared = await library.resolveReadablePath(second);

    await library.replaceManagedContent(
      documentId: first.id,
      bytes: bytes('%PDF-1.4 changed'),
    );

    expect(File(shared).existsSync(), isTrue);
    expect(
      latin1.decode(
        await File(await library.resolveReadablePath(second)).readAsBytes(),
        allowInvalid: true,
      ),
      '%PDF-1.4 same',
    );
  });
}
