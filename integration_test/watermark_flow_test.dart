@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/numbering_repository_impl.dart';
import 'package:folio/domain/numbering/page_numbers.dart';
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

    // A watermark stream is deflated only when that actually shrinks the file,
    // so this uses a mark long enough to qualify. If /Filter or /Length
    // disagreed with the bytes, PDFium would fail to inflate the stream and
    // the mark would simply not be there - the reader is the only thing that
    // can confirm a compressed stream is well-formed.
    test('the reader inflates the compressed watermark stream', () async {
      const wordy = Watermark(
        text: 'CONFIDENTIAL DRAFT - NOT FOR DISTRIBUTION OR REVIEW',
      );

      final src = await seed('Compressed.pdf');
      final out = await subject.apply(src.id, wordy);

      final path = await library.resolveReadablePath(out);
      final raw = await File(path).readAsBytes();
      final text = latin1.decode(raw, allowInvalid: true);

      expect(
        text,
        contains('/FlateDecode'),
        reason: 'this mark is long enough that compression pays',
      );
      expect(
        text,
        isNot(contains('CONFIDENTIAL DRAFT')),
        reason: 'the mark must not be sitting in the file as plain text',
      );

      final h = await engine.open(FileSource(path));
      final extracted = await engine.extractText(h, 0);
      await engine.close(h);

      expect(extracted!.fullText, contains('CONFIDENTIAL DRAFT'));
    });
  });

  group('removing a watermark Folio applied', () {
    const wordy = Watermark(
      text: 'CONFIDENTIAL DRAFT - NOT FOR DISTRIBUTION OR REVIEW',
    );

    // The decisive one: after removal the page must render exactly as it did
    // before the mark was ever applied.
    test('the page returns to how it looked before', () async {
      final src = await seed('Undo.pdf');
      final before = await render(src, 0);

      final marked = await subject.apply(src.id, wordy);
      expect(
        diff(before, await render(marked, 0)),
        greaterThan(200),
        reason: 'the premise: the watermark visibly changed the page',
      );

      final cleaned = await subject.remove(marked.id);

      expect(diff(before, await render(cleaned, 0)), 0);
    });

    test('every page is cleaned, not just the first', () async {
      final src = await seed('UndoAll.pdf');
      final before = [for (var i = 0; i < 3; i++) await render(src, i)];

      final marked = await subject.apply(src.id, wordy);
      final cleaned = await subject.remove(marked.id);

      for (var i = 0; i < 3; i++) {
        expect(diff(before[i], await render(cleaned, i)), 0, reason: 'page $i');
      }
    });

    test('the text is still extractable afterwards', () async {
      final src = await seed('UndoText.pdf');
      final marked = await subject.apply(src.id, wordy);
      final cleaned = await subject.remove(marked.id);

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(cleaned)),
      );
      final text = await engine.extractText(h, 0);
      await engine.close(h);

      expect(text!.fullText, contains('Confidential'));
      expect(text.fullText, isNot(contains('NOT FOR DISTRIBUTION')));
    });

    // A mark Folio did not apply leaves nothing it can identify.
    test('a document with no Folio watermark is refused', () async {
      final src = await seed('Unmarked.pdf');

      await expectLater(
        subject.remove(src.id),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });

    test('the watermarked document is left alone', () async {
      final src = await seed('Keep.pdf');
      final marked = await subject.apply(src.id, wordy);
      final markedBytes = await File(
        await library.resolveReadablePath(marked),
      ).readAsBytes();

      await subject.remove(marked.id);

      expect(
        await File(await library.resolveReadablePath(marked)).readAsBytes(),
        markedBytes,
      );
    });
  });

  // Page numbers are page content, like a watermark: a number any viewer can
  // select and delete is not a page number.
  group('numbering pages', () {
    late NumberingRepositoryImpl numbering;

    setUp(() {
      numbering = NumberingRepositoryImpl(
        library: library,
        documents: DocumentWriter(
          library: library,
          writer: SafeFileWriter(),
          libraryRoot: root,
        ),
      );
    });

    test('a number appears on the page and is extractable', () async {
      final src = await seed('Numbered.pdf');
      final before = await render(src, 0);

      final out = await numbering.apply(
        src.id,
        const PageNumbering(format: NumberFormat.ofTotal),
      );

      expect(
        diff(before, await render(out, 0)),
        greaterThan(20),
        reason: 'something was drawn near the foot of the page',
      );

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final text = await engine.extractText(h, 0);
      await engine.close(h);

      expect(text!.fullText, contains('1 of 3'));
    });

    test('every page is numbered, and each differently', () async {
      final src = await seed('AllPages.pdf');
      final out = await numbering.apply(src.id, const PageNumbering());

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final texts = [
        for (var i = 0; i < 3; i++) (await engine.extractText(h, i))!.fullText,
      ];
      await engine.close(h);

      expect(texts[0], contains('1'));
      expect(texts[1], contains('2'));
      expect(texts[2], contains('3'));
    });

    // The page's own text must survive: a numbering pass that replaced
    // /Contents would leave a page with nothing but its number.
    test('the page keeps its own content', () async {
      final src = await seed('Keeps.pdf');
      final out = await numbering.apply(src.id, const PageNumbering());

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final text = await engine.extractText(h, 0);
      await engine.close(h);

      expect(text!.fullText, contains('Confidential'));
    });

    test('a skipped first page really has no number', () async {
      final src = await seed('Skipped.pdf');
      final before = await render(src, 0);

      final out = await numbering.apply(
        src.id,
        const PageNumbering(skipFirst: true),
      );

      expect(
        diff(before, await render(out, 0)),
        0,
        reason: 'page one is untouched, not merely unnumbered',
      );
    });

    test('the source document is untouched', () async {
      final src = await seed('Source.pdf');
      final bytes = await File(
        await library.resolveReadablePath(src),
      ).readAsBytes();

      await numbering.apply(src.id, const PageNumbering());

      expect(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
        bytes,
      );
    });
  });
}
