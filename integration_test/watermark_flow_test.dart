@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/watermark_repository_impl.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late WatermarkRepositoryImpl subject;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wm_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = WatermarkRepositoryImpl(
      library: library,
      documents: DocumentWriter(
        library: library,
        writer: SafeFileWriter(),
        libraryRoot: root,
      ),
    );
    engine = PdfrxEngine();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<List<int>> render(LibraryDocument d, int pageIndex) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final px = (await engine.renderPage(
      h,
      pageIndex,
      targetWidthPx: 400,
      targetHeightPx: 566,
    )).bgraPixels;
    await engine.close(h);
    return px;
  }

  int diff(List<int> a, List<int> b) {
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) n++;
    }
    return n;
  }

  Future<LibraryDocument> seed(String name) async => library.importFile(
    await fixturePath('sample_3page.pdf'),
    displayName: name,
  );

  const draft = Watermark(text: 'DRAFT');

  group('watermark flow', () {
    test('a watermark draws on the first page', () async {
      final src = await seed('First.pdf');
      final before = await render(src, 0);

      final out = await subject.apply(src.id, draft);

      expect(diff(before, await render(out, 0)), greaterThan(500));
    });

    // A writer that stops after page one produces something that looks like
    // it worked.
    test('it draws on the last page too', () async {
      final src = await seed('Last.pdf');
      final before = await render(src, 2);

      final out = await subject.apply(src.id, draft);

      expect(
        diff(before, await render(out, 2)),
        greaterThan(500),
        reason: 'every page, not just the first',
      );
    });

    test('the document still opens with the same page count', () async {
      final src = await seed('Count.pdf');
      final out = await subject.apply(src.id, draft);

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      expect(h.pageCount, 3);
      await engine.close(h);
    });

    test('the source document is byte-identical afterwards', () async {
      final src = await seed('Untouched.pdf');
      final path = await library.resolveReadablePath(src);
      final before = sha256.convert(await File(path).readAsBytes()).toString();

      await subject.apply(src.id, draft);

      expect(sha256.convert(await File(path).readAsBytes()).toString(), before);
    });

    test('metadata survives', () async {
      final src = await library.importFile(
        await fixturePath('with_metadata.pdf'),
        displayName: 'Meta.pdf',
      );
      final before = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
      )!;

      final out = await subject.apply(src.id, draft);

      final after = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(out)).readAsBytes(),
      )!;
      expect(after.title, before.title);
      expect(after.author, before.author);
    });

    // An unbalanced content stream corrupts everything after it. Text that is
    // still extractable is the cheapest proof the page survived.
    test('the page own text is still extractable', () async {
      final src = await seed('Text.pdf');
      final out = await subject.apply(src.id, draft);

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final text = await engine.extractText(h, 0);
      await engine.close(h);

      expect(text!.fullText, contains('Confidential'));
    });
  });
}
