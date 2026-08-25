import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/page_operations_repository_impl.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:folio/engine/pdfrx_page_editor.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late PageOperationsRepositoryImpl ops;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ops_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    engine = PdfrxEngine();
    ops = PageOperationsRepositoryImpl(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: root,
      editor: PdfrxPageEditor(engine),
      openSource: (doc) async =>
          engine.open(FileSource(await library.resolveReadablePath(doc))),
      closeSource: engine.close,
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<LibraryDocument> seed(String fixture, String name) async =>
      library.importFile(await fixturePath(fixture), displayName: name);

  Future<String> hashOf(LibraryDocument doc) async => sha256
      .convert(await File(await library.resolveReadablePath(doc)).readAsBytes())
      .toString();

  Future<PdfDocumentHandle> openOutput(LibraryDocument doc) async =>
      engine.open(FileSource(await library.resolveReadablePath(doc)));

  group('page operation flows', () {
    test('reorder: order survives and the source is untouched', () async {
      final src = await seed('sample_3page.pdf', 'Invoice.pdf');
      final before = await hashOf(src);

      final out = await ops.apply(
        sourceDocumentId: src.id,
        slots: [
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 2),
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 1),
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 0),
        ],
      );

      final handle = await openOutput(out);
      final first = await engine.extractText(handle, 0);
      expect(first!.fullText, contains('Appendix A'));
      await engine.close(handle);

      expect(await hashOf(src), before, reason: 'source must be untouched');
    });

    test('rotate: geometry swaps and the source is untouched', () async {
      final src = await seed('sample_3page.pdf', 'Invoice.pdf');
      final before = await hashOf(src);

      final out = await ops.apply(
        sourceDocumentId: src.id,
        slots: [
          PageSlot(
            sourceDocumentId: src.id,
            sourcePageIndex: 0,
            quarterTurns: 1,
          ),
        ],
      );

      final handle = await openOutput(out);
      final info = await engine.pageInfo(handle, 0);
      expect(info.isLandscape, isTrue);
      await engine.close(handle);

      expect(await hashOf(src), before);
    });

    test(
      'delete: the right pages survive and the source is untouched',
      () async {
        final src = await seed('sample_3page.pdf', 'Invoice.pdf');
        final before = await hashOf(src);

        final out = await ops.apply(
          sourceDocumentId: src.id,
          slots: [PageSlot(sourceDocumentId: src.id, sourcePageIndex: 1)],
        );

        final handle = await openOutput(out);
        expect(handle.pageCount, 1);
        final text = await engine.extractText(handle, 0);
        expect(text!.fullText, contains('Terms and Conditions'));
        await engine.close(handle);

        expect(await hashOf(src), before);
      },
    );

    test('extract: only the selected pages appear', () async {
      final src = await seed('sample_3page.pdf', 'Invoice.pdf');
      final before = await hashOf(src);

      final out = await ops.extractPages(
        sourceDocumentId: src.id,
        slots: [
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 2),
        ],
      );

      expect(out.displayName, 'Invoice (2 pages).pdf');
      final handle = await openOutput(out);
      expect(handle.pageCount, 2);
      await engine.close(handle);

      expect(await hashOf(src), before);
    });

    test('split: N documents with the expected page counts', () async {
      final src = await seed('sample_3page.pdf', 'Invoice.pdf');
      final before = await hashOf(src);

      final parts = await ops.split(
        sourceDocumentId: src.id,
        groups: const [
          [0],
          [1, 2],
        ],
      );

      expect(parts, hasLength(2));
      final a = await openOutput(parts[0]);
      expect(a.pageCount, 1);
      await engine.close(a);
      final b = await openOutput(parts[1]);
      expect(b.pageCount, 2);
      await engine.close(b);

      expect(await hashOf(src), before);
    });

    test('merge: page counts add and both sources are untouched', () async {
      final a = await seed('sample_3page.pdf', 'A.pdf');
      final b = await seed('pages_10.pdf', 'B.pdf');
      final beforeA = await hashOf(a);
      final beforeB = await hashOf(b);

      final merged = await ops.merge(documentIds: [a.id, b.id]);

      final handle = await openOutput(merged);
      expect(handle.pageCount, 13, reason: '3 + 10');
      await engine.close(handle);

      expect(await hashOf(a), beforeA);
      expect(await hashOf(b), beforeB);
    });

    test('duplicate: the copy is byte-identical in content', () async {
      final src = await seed('sample_3page.pdf', 'Invoice.pdf');

      final out = await ops.apply(
        sourceDocumentId: src.id,
        slots: [
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 0),
        ],
      );

      final handle = await openOutput(out);
      expect(handle.pageCount, 2);
      final first = await engine.extractText(handle, 0);
      final second = await engine.extractText(handle, 1);
      expect(first!.fullText, second!.fullText);
      await engine.close(handle);
    });

    test('insert: pages land at the chosen position', () async {
      final a = await seed('sample_3page.pdf', 'A.pdf');
      final b = await seed('pages_10.pdf', 'B.pdf');

      final out = await ops.apply(
        sourceDocumentId: a.id,
        slots: [
          PageSlot(sourceDocumentId: a.id, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: b.id, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: a.id, sourcePageIndex: 1),
        ],
      );

      final handle = await openOutput(out);
      expect(handle.pageCount, 3);
      final middle = await engine.extractText(handle, 1);
      expect(middle!.fullText, contains('Section 1'));
      await engine.close(handle);
    });

    // The data-loss bug this sub-project exists to fix: page operations used to
    // discard the source's /Info entirely.
    test('metadata survives a page operation', () async {
      final src = await seed('with_metadata.pdf', 'Has Metadata.pdf');

      final before = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
      );
      expect(before!.title, 'FOLIO-PROBE-TITLE');

      final out = await ops.apply(
        sourceDocumentId: src.id,
        slots: [
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 1),
          PageSlot(sourceDocumentId: src.id, sourcePageIndex: 0),
        ],
      );

      final after = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(out)).readAsBytes(),
      );
      expect(after, isNotNull, reason: 'the output must carry an /Info');
      expect(after!.title, 'FOLIO-PROBE-TITLE');
      expect(after.author, 'FOLIO-PROBE-AUTHOR');
      expect(after.subject, 'FOLIO-PROBE-SUBJECT');

      // And the patched document must still be a valid PDF.
      final handle = await openOutput(out);
      expect(handle.pageCount, 2);
      final first = await engine.extractText(handle, 0);
      expect(first!.fullText, contains('Terms and Conditions'));
      await engine.close(handle);
    });

    test('metadata survives split, on every part', () async {
      final src = await seed('with_metadata.pdf', 'Has Metadata.pdf');

      final parts = await ops.split(
        sourceDocumentId: src.id,
        groups: const [
          [0],
          [1, 2],
        ],
      );

      for (final part in parts) {
        final meta = PdfMetadata.readFrom(
          await File(await library.resolveReadablePath(part)).readAsBytes(),
        );
        expect(meta?.title, 'FOLIO-PROBE-TITLE');
      }
    });

    test('a source with no metadata still produces a valid document', () async {
      final src = await seed('sample_3page.pdf', 'Plain.pdf');

      final out = await ops.apply(
        sourceDocumentId: src.id,
        slots: [PageSlot(sourceDocumentId: src.id, sourcePageIndex: 0)],
      );

      final handle = await openOutput(out);
      expect(handle.pageCount, 1);
      await engine.close(handle);
    });
  });
}
