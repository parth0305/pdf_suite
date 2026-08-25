import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/page_operations_repository_impl.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/engine/pdf_types.dart';

import '../../fakes/fake_page_editor.dart';

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late FakePageEditor editor;
  late PageOperationsRepositoryImpl ops;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('page_ops');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
    editor = FakePageEditor();
    ops = PageOperationsRepositoryImpl(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
      editor: editor,
      openSource: (doc) async =>
          PdfDocumentHandle(id: 'h${doc.id}', pageCount: 3),
      closeSource: (_) async {},
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<int> seed(String name) async {
    final f = File('${sandbox.path}/src_$name')
      ..writeAsBytesSync([37, 80, 68, 70, 1, 2, 3]);
    final doc = await library.importFile(f.path, displayName: name);
    return doc.id;
  }

  group('apply', () {
    test('creates a new entry and leaves the original untouched', () async {
      final id = await seed('Invoice.pdf');
      final before = await library.resolveReadablePath(
        (await library.all()).single,
      );
      final beforeBytes = await File(before).readAsBytes();

      final result = await ops.apply(
        sourceDocumentId: id,
        slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      );

      expect(result.displayName, 'Invoice (edited).pdf');
      expect(await library.all(), hasLength(2));
      expect(
        await File(before).readAsBytes(),
        beforeBytes,
        reason: 'the original file must be byte-identical afterwards',
      );
    });

    test('an empty slot list is rejected before anything is written', () async {
      final id = await seed('Invoice.pdf');

      await expectLater(
        ops.apply(sourceDocumentId: id, slots: const []),
        throwsA(isA<EmptyDocument>()),
      );
      expect(await library.all(), hasLength(1));
    });

    // Inserting pages from another document leaves its id in the slot list, so
    // apply must open every document the slots reference, not only the source.
    test('applies slots that reference more than one document', () async {
      final a = await seed('A.pdf');
      final b = await seed('B.pdf');

      final result = await ops.apply(
        sourceDocumentId: a,
        slots: [
          PageSlot(sourceDocumentId: a, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: b, sourcePageIndex: 0),
        ],
      );

      expect(result.displayName, 'A (edited).pdf');
      expect(editor.calls.single, hasLength(2));
    });

    test('editing an edited document numbers the suffix', () async {
      final id = await seed('Invoice.pdf');
      final once = await ops.apply(
        sourceDocumentId: id,
        slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      );
      final twice = await ops.apply(
        sourceDocumentId: once.id,
        slots: const [PageSlot(sourceDocumentId: 2, sourcePageIndex: 0)],
      );

      expect(twice.displayName, 'Invoice (edited 2).pdf');
    });
  });

  group('merge', () {
    test('produces one document and leaves both sources in place', () async {
      final a = await seed('A.pdf');
      final b = await seed('B.pdf');

      final merged = await ops.merge(documentIds: [a, b]);

      expect(merged.displayName, contains('A'));
      expect(await library.all(), hasLength(3));
    });

    test('merging fewer than two documents is rejected', () async {
      final a = await seed('A.pdf');
      await expectLater(
        ops.merge(documentIds: [a]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('extractPages', () {
    test('names the output by page count', () async {
      final id = await seed('Invoice.pdf');
      final result = await ops.extractPages(
        sourceDocumentId: id,
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 2),
        ],
      );
      expect(result.displayName, 'Invoice (2 pages).pdf');
    });
  });

  group('split', () {
    test('produces one document per group, numbered', () async {
      final id = await seed('Invoice.pdf');
      final parts = await ops.split(
        sourceDocumentId: id,
        groups: const [
          [0],
          [1, 2],
        ],
      );

      expect(parts, hasLength(2));
      expect(parts.first.displayName, 'Invoice (part 1).pdf');
      expect(parts.last.displayName, 'Invoice (part 2).pdf');
      expect(await library.all(), hasLength(3));
    });

    test('an empty group list is rejected', () async {
      final id = await seed('Invoice.pdf');
      await expectLater(
        ops.split(sourceDocumentId: id, groups: const []),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
