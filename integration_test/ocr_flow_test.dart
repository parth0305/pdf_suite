@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/ocr/ocr_engine.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/ocr_repository_impl.dart';
import 'package:folio/data/repositories/scanner_repository_impl.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/scanner/scanned_page.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'jpeg_fixtures.dart';
import 'ocr_page_jpeg.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late ScannerRepositoryImpl scanner;
  late OcrRepositoryImpl subject;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ocr_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    final documents = DocumentWriter(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    scanner = ScannerRepositoryImpl(documents: documents);
    engine = PdfrxEngine();
    subject = OcrRepositoryImpl(
      library: library,
      documents: documents,
      engine: PdfrxEngine(),
      ocr: const TesseractOcrEngine(),
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<String> textOf(LibraryDocument d, int pageIndex) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final text = await engine.extractText(h, pageIndex);
    await engine.close(h);
    return text?.fullText ?? '';
  }

  Future<List<int>> render(LibraryDocument d, int pageIndex) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final px = (await engine.renderPage(
      h,
      pageIndex,
      targetWidthPx: 300,
      targetHeightPx: 424,
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

  /// A scan of a page of words — the exact thing OCR exists for.
  Future<LibraryDocument> scanOfText() async =>
      scanner.save([ScannedPage(kTextPageJpeg)]);

  group('OCR', () {
    // THE assertion. Before OCR the document has no text at all; afterwards a
    // reader can extract the words that are visible in the image.
    test('a scanned page becomes searchable', () async {
      final scan = await scanOfText();

      expect(
        await textOf(scan, 0),
        isEmpty,
        reason: 'the premise: a scan has no text layer',
      );

      final recognised = await subject.recognise(scan.id);
      final text = await textOf(recognised, 0);

      expect(text.toLowerCase(), contains('invoice'));
      expect(text.toLowerCase(), contains('acme'));
    });

    // The text layer must not be visible. If it renders, every scan gets a
    // second copy of its own words printed over it.
    test('the text layer is invisible', () async {
      final scan = await scanOfText();
      final before = await render(scan, 0);

      final recognised = await subject.recognise(scan.id);

      expect(
        diff(before, await render(recognised, 0)),
        0,
        reason: 'OCR must not change a single pixel',
      );
    });

    test('the scan itself is still drawn', () async {
      final scan = await scanOfText();
      final recognised = await subject.recognise(scan.id);
      final pixels = await render(recognised, 0);

      // A page that lost its image would render as blank white.
      var dark = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i] < 128) dark++;
      }
      expect(dark, greaterThan(50), reason: 'there is ink on the page');
    });

    // Nothing above this would notice if the positioned path stopped being
    // used: the approximate fallback also produces extractable text, so every
    // other assertion passes either way. This is the only test that observes
    // WHERE the words landed.
    //
    // The distinguishing property is the gap between two adjacent lines. The
    // fallback spreads lines evenly over the whole page, so two neighbours end
    // up a quarter of a page apart; real positions keep them adjacent.
    test('words land where they appear in the image', () async {
      if (!Platform.isAndroid) {
        markTestSkipped('word positions need hOCR, which only Android has');
        return;
      }

      final scan = await scanOfText();
      final recognised = await subject.recognise(scan.id);

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(recognised)),
      );
      final page = (await engine.extractText(h, 0))!;
      final size = await engine.pageInfo(h, 0);
      await engine.close(h);

      double topOf(String word) {
        final at = page.fullText.toLowerCase().indexOf(word);
        expect(at, greaterThanOrEqualTo(0), reason: 'OCR must have read $word');
        return page.charRects[at].top;
      }

      final gap = (topOf('invoice') - topOf('acme')).abs();

      expect(
        gap,
        lessThan(size.heightPt / 8),
        reason:
            'adjacent lines in the scan stay adjacent on the page; the '
            'fallback would put them a quarter of a page apart',
      );
      expect(
        gap,
        greaterThan(0),
        reason: 'and they are not on top of one another',
      );

      // The gap alone is mirror-symmetric: dropping the y-flip moves every
      // word but keeps neighbours the same distance apart, so that assertion
      // passes upside-down. The title's ABSOLUTE position is what catches it.
      expect(
        topOf('invoice'),
        greaterThan(size.heightPt / 2),
        reason: 'the title is at the TOP of the page, not the bottom',
      );
    });

    test('the source document is untouched', () async {
      final scan = await scanOfText();
      final before = await File(
        await library.resolveReadablePath(scan),
      ).readAsBytes();

      await subject.recognise(scan.id);

      expect(
        await File(await library.resolveReadablePath(scan)).readAsBytes(),
        before,
      );
    });

    test('the result is a new document', () async {
      final scan = await scanOfText();
      final recognised = await subject.recognise(scan.id);

      expect(recognised.id, isNot(scan.id));
      expect(recognised.displayName, contains('edited'));
    });

    test('a document where nothing is recognised is refused', () async {
      // A blank half-red half-blue swatch has no text in it at all.
      final blank = await scanner.save([ScannedPage(kColourJpeg)]);

      await expectLater(subject.recognise(blank.id), throwsArgumentError);
    });
  });
}
