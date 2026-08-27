@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/scanner_repository_impl.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/scanner/scanned_page.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'jpeg_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late ScannerRepositoryImpl subject;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('scan_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = ScannerRepositoryImpl(
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
      targetWidthPx: 200,
      targetHeightPx: 283,
    )).bgraPixels;
    await engine.close(h);
    return px;
  }

  Future<int> pageCount(LibraryDocument d) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final n = h.pageCount;
    await engine.close(h);
    return n;
  }

  group('scanner', () {
    // THE assertion. The unit tests can only prove the JPEG bytes were copied
    // into the file; only a reader can prove a /DCTDecode image Folio wrote is
    // one PDFium accepts.
    test('a scanned page renders the image it was given', () async {
      final doc = await subject.save([ScannedPage(kColourJpeg)]);
      final pixels = await render(doc, 0);

      // The fixture is left half red, right half blue, fitted to A4 and
      // centred: 595 wide of 595, so it fills the width and is centred
      // vertically. At 200x283 the image occupies rows ~41..241.
      int at(int x, int y) => (y * 200 + x) * 4;
      final left = pixels.sublist(at(50, 140), at(50, 140) + 4);
      final right = pixels.sublist(at(150, 140), at(150, 140) + 4);

      expect(left[2], greaterThan(180), reason: 'left half red');
      expect(left[0], lessThan(80), reason: 'and not blue');
      expect(right[0], greaterThan(180), reason: 'right half blue');
      expect(right[2], lessThan(80), reason: 'and not red');
    });

    test('one page per captured image', () async {
      final doc = await subject.save([
        ScannedPage(kColourJpeg),
        ScannedPage(kGrayJpeg),
        ScannedPage(kColourJpeg),
      ]);

      expect(await pageCount(doc), 3);
    });

    // This proves a single-component JPEG renders at all. It does NOT guard
    // the /ColorSpace choice: declaring /DeviceRGB for this image was tried as
    // a mutation and PDFium rendered it correctly anyway, because libjpeg
    // reads the component count out of the JPEG itself. The unit test that
    // asserts /DeviceGray is written is the only guard, and other readers are
    // not promised to be as forgiving.
    test('a grayscale page renders as grey, not as noise', () async {
      final doc = await subject.save([ScannedPage(kGrayJpeg)]);
      final pixels = await render(doc, 0);

      final i = (140 * 200 + 50) * 4;
      final b = pixels[i], g = pixels[i + 1], r = pixels[i + 2];

      expect(
        (r - g).abs() + (g - b).abs(),
        lessThan(30),
        reason: 'a grey pixel has near-equal channels',
      );
    });

    test('page order matches capture order', () async {
      final doc = await subject.save([
        ScannedPage(kGrayJpeg),
        ScannedPage(kColourJpeg),
      ]);

      final first = await render(doc, 0);
      final second = await render(doc, 1);

      int spread(List<int> px) {
        final i = (140 * 200 + 50) * 4;
        return (px[i + 2] - px[i]).abs();
      }

      expect(spread(first), lessThan(30), reason: 'page 1 is the grey one');
      expect(spread(second), greaterThan(100), reason: 'page 2 is the red one');
    });

    test('the document lands in the library with a dated name', () async {
      final doc = await subject.save([ScannedPage(kColourJpeg)]);

      expect(doc.displayName, startsWith('Scan '));
      expect((await library.all()).map((d) => d.id), contains(doc.id));
    });

    // Folio now PRODUCES documents with no text layer. Asserting it here means
    // the day OCR arrives, this test fails and has to be updated deliberately.
    test(
      'a scan has no text layer, which is the documented limitation',
      () async {
        final doc = await subject.save([ScannedPage(kColourJpeg)]);

        final h = await engine.open(
          FileSource(await library.resolveReadablePath(doc)),
        );
        final text = await engine.extractText(h, 0);
        await engine.close(h);

        expect(text?.fullText ?? '', isEmpty);
      },
    );

    test('an empty scan is refused', () async {
      await expectLater(subject.save(const []), throwsArgumentError);
    });
  });
}
