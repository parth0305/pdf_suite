@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/compression_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

/// A document containing a genuinely duplicated font object, which is what
/// merging two documents produces and what dedupe exists for. None of the
/// generated fixtures has one, so nothing else here exercises that path.
String _withDuplicateFont() {
  final font =
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding /FirstChar 32 /LastChar 255 '
      '/Widths [${List.filled(80, '500').join(' ')}] >>';
  const body = 'BT /F1 24 Tf 60 700 Td (DUPLICATE-FONT-PROBE) Tj ET';

  return '%PDF-1.4\n'
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
      '/MediaBox [0 0 595 842] >>\nendobj\n'
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 7 0 R '
      '/Resources << /Font << /F1 4 0 R >> >> >>\nendobj\n'
      '4 0 obj\n$font\nendobj\n'
      '5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 7 0 R '
      '/Resources << /Font << /F1 6 0 R >> >> >>\nendobj\n'
      '6 0 obj\n$font\nendobj\n'
      '7 0 obj\n<< /Length ${body.length} >>\nstream\n$body\nendstream\n'
      'endobj\n'
      'xref\n0 8\n0000000000 65535 f \n'
      'trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late CompressionRepositoryImpl subject;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zip_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = CompressionRepositoryImpl(
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

  Future<LibraryDocument> seed(String name) async => library.importFile(
    await fixturePath('sample_3page.pdf'),
    displayName: name,
  );

  /// A 200-page document. Its two hundred uncompressed content streams are
  /// what makes compression worth doing; a three-page file is too small for
  /// the saving to beat the rewrite's own overhead.
  Future<LibraryDocument> seedLarge(String name) async =>
      library.importFile(await fixturePath('pages_200.pdf'), displayName: name);

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

  Future<String> textOf(LibraryDocument d, int pageIndex) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final text = await engine.extractText(h, pageIndex);
    await engine.close(h);
    return text?.fullText ?? '';
  }

  int diff(List<int> a, List<int> b) {
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) n++;
    }
    return n;
  }

  group('compression', () {
    // THE assertion. Compression is lossless, so every page must come back
    // pixel-identical. Anything else means bytes were lost, not saved.
    test('every page renders exactly as before', () async {
      final src = await seed('Zip.pdf');
      final before = [for (var i = 0; i < 3; i++) await render(src, i)];

      final result = await subject.analyse(src.id);
      final out = await subject.save(src.id, result);

      for (var i = 0; i < 3; i++) {
        expect(
          diff(before[i], await render(out, i)),
          0,
          reason: 'page ${i + 1} must be untouched',
        );
      }
    });

    test('the text is unchanged', () async {
      final src = await seed('ZipText.pdf');
      final before = await textOf(src, 0);

      final result = await subject.analyse(src.id);
      final out = await subject.save(src.id, result);

      expect(await textOf(out, 0), before);
      expect(before, contains('Confidential'));
    });

    test('a document with room to shrink actually shrinks', () async {
      final src = await seedLarge('ZipSize.pdf');
      final result = await subject.analyse(src.id);

      expect(result.savedBytes, greaterThan(0));
      expect(result.worthDoing, isTrue);

      final out = await subject.save(src.id, result);
      expect(out.sizeBytes, lessThan(src.sizeBytes));
    });

    // Measured, not hypothetical: on this three-page fixture the rewrite's own
    // overhead - a fresh cross-reference table, an /ID, the binary comment -
    // exceeds what deflating its streams saves, and the file comes out NINE
    // BYTES LARGER. Reporting that honestly is the whole reason the result is
    // offered rather than applied.
    test('a document with nothing to gain reports so', () async {
      final src = await seed('ZipTight.pdf');
      final result = await subject.analyse(src.id);

      expect(result.worthDoing, isFalse);
    });

    // The number shown to the user is the file they get, not a prediction of
    // it. Analysing and then saving must not produce a different size.
    test('the reported saving is what the stored file delivers', () async {
      final src = await seedLarge('ZipPromise.pdf');
      final result = await subject.analyse(src.id);
      final out = await subject.save(src.id, result);

      expect(out.sizeBytes, result.compressedBytes);
    });

    test('the page count survives', () async {
      final src = await seed('ZipPages.pdf');
      final result = await subject.analyse(src.id);
      final out = await subject.save(src.id, result);

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final pages = h.pageCount;
      await engine.close(h);

      expect(pages, 3);
    });

    test('the source document is untouched', () async {
      final src = await seed('ZipSource.pdf');
      final before = await File(
        await library.resolveReadablePath(src),
      ).readAsBytes();

      final result = await subject.analyse(src.id);
      await subject.save(src.id, result);

      expect(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
        before,
      );
    });

    test('analysing writes nothing', () async {
      final src = await seed('ZipDry.pdf');
      final before = (await library.all()).length;

      await subject.analyse(src.id);

      expect((await library.all()).length, before);
    });
  });

  group('deduplication', () {
    Future<LibraryDocument> seedDuplicated(String name) async {
      final f = File('${root.path}/$name')
        ..writeAsStringSync(_withDuplicateFont());
      return library.importFile(f.path, displayName: name);
    }

    // Nothing else on device exercises dedupe: no generated fixture contains a
    // duplicated object, so mutating the remapping was green across the whole
    // integration suite.
    test(
      'a duplicated font is collapsed and both pages still render',
      () async {
        final src = await seedDuplicated('Dup.pdf');
        final before = [for (var i = 0; i < 2; i++) await render(src, i)];

        final result = await subject.analyse(src.id);
        expect(
          result.duplicateBytes,
          greaterThan(200),
          reason: 'the second font object is the duplicate',
        );

        final out = await subject.save(src.id, result);

        for (var i = 0; i < 2; i++) {
          expect(
            diff(before[i], await render(out, i)),
            0,
            reason: 'page ${i + 1} must look identical after the collapse',
          );
        }
      },
    );

    test('the collapsed document still has both pages of text', () async {
      final src = await seedDuplicated('DupText.pdf');
      final result = await subject.analyse(src.id);
      final out = await subject.save(src.id, result);

      expect(await textOf(out, 0), contains('DUPLICATE-FONT-PROBE'));
      expect(
        await textOf(out, 1),
        contains('DUPLICATE-FONT-PROBE'),
        reason: 'the page whose font was collapsed must still find one',
      );
    });
  });
}
