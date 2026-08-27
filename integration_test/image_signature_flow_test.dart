@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/data/signature/signature_photo_source.dart';
import 'package:folio/domain/signature/background_removal.dart';
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
  late AnnotationRepositoryImpl annotations;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('imgsig');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    annotations = AnnotationRepositoryImpl(
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

  Future<List<int>> render(LibraryDocument d) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final px = (await engine.renderPage(
      h,
      0,
      targetWidthPx: 400,
      targetHeightPx: 566,
    )).bgraPixels;
    await engine.close(h);
    return px;
  }

  /// A photographed signature: a dark bar on light paper, run through the real
  /// extraction rather than hand-built with alpha already set.
  ImageAnnotation photographedSignature() {
    const w = 40, h = 20;
    final photo = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Ink across the middle third; paper elsewhere.
        final ink = y >= 8 && y <= 11;
        final v = ink ? 30 : 235;
        photo.addAll([v, v, v, 255]);
      }
    }

    final extracted = removeBackground(photo, w, h);
    expect(extracted.isUsable, isTrue, reason: 'the fixture must be usable');

    return ImageAnnotation(
      pageIndex: 0,
      rect: const TextRect(left: 100, top: 500, right: 400, bottom: 350),
      rgba: extracted.rgba,
      pixelWidth: w,
      pixelHeight: h,
    );
  }

  group('photographed signature', () {
    // THE assertion. The signature must appear AND its paper must not: an
    // /SMask that PDFium ignored would drop an opaque block over the page.
    test('the ink is drawn and the paper stays transparent', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Signed.pdf',
      );
      final before = await render(src);

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [photographedSignature()],
      );
      final after = await render(out);

      // The rect spans x 100-400pt of a 595pt page and y 350-500pt of 842.
      // PDF y counts UP from the bottom while render rows count DOWN from the
      // top, so the rect occupies rows (842-500)/842*566 = 230 through
      // (842-350)/842*566 = 331. Sampling rows 195-285, as this first did,
      // put a third of the "inside" band ABOVE the rect - pixels that never
      // change whatever the mask does, which is why dropping the /SMask
      // altogether still passed.
      int at(int x, int y) => (y * 400 + x) * 4;

      var darkened = 0;
      var unchangedInside = 0;
      for (var y = 235; y < 325; y++) {
        for (var x = 75; x < 260; x++) {
          final i = at(x, y);
          if (after[i] < before[i] - 40) darkened++;
          if (after[i] == before[i]) unchangedInside++;
        }
      }

      // The mask's effect, as a number: with it only the ink changes pixels.
      // Without it the whole rect is painted and this leaps from about 4,000
      // to about 20,000.
      var totalChanged = 0;
      for (var i = 0; i < before.length; i += 4) {
        if (after[i] != before[i]) totalChanged++;
      }
      expect(
        totalChanged,
        lessThan(10000),
        reason: 'an ignored /SMask paints the entire rect',
      );

      expect(darkened, greaterThan(200), reason: 'the ink was drawn');
      expect(
        unchangedInside,
        greaterThan(2000),
        reason:
            'most of the rect is untouched paper - if the mask were '
            'ignored, the whole rect would have changed',
      );
    });

    test('the rest of the page is untouched', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Elsewhere.pdf',
      );
      final before = await render(src);

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [photographedSignature()],
      );
      final after = await render(out);

      // Well above the signature's rect.
      var changed = 0;
      for (var y = 0; y < 150; y++) {
        for (var x = 0; x < 400; x++) {
          if (after[(y * 400 + x) * 4] != before[(y * 400 + x) * 4]) changed++;
        }
      }

      expect(changed, 0);
    });

    test('the source document is untouched', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Source.pdf',
      );
      final bytes = await File(
        await library.resolveReadablePath(src),
      ).readAsBytes();

      await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [photographedSignature()],
      );

      expect(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
        bytes,
      );
    });
  });

  // The whole path a photograph takes: encoded bytes in, decoded, ink
  // extracted, re-encoded for preview. Only a device can run it - decoding
  // goes through dart:ui, which needs a real engine.
  group('the photograph pipeline', () {
    test('a real PNG decodes, extracts and re-encodes', () async {
      // A PNG of dark ink on light paper, built here so the test owns its
      // input rather than depending on a fixture file.
      const w = 32, h = 16;
      final rgba = <int>[];
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final ink = y >= 6 && y <= 9;
          final v = ink ? 25 : 240;
          rgba.addAll([v, v, v, 255]);
        }
      }
      final png = await encodeRgbaToPng(rgba, w, h);

      final photo = await SignaturePhotoSource.extract(png);

      expect(photo.width, w);
      expect(photo.height, h);
      expect(photo.isUsable, isTrue);

      // Paper transparent, ink opaque - the point of the whole feature.
      int alphaAt(int x, int y) => photo.rgba[(y * w + x) * 4 + 3];
      expect(alphaAt(16, 7), 255, reason: 'on the ink');
      expect(alphaAt(16, 1), 0, reason: 'on the paper');
    });

    test('the preview PNG keeps its transparency', () async {
      const w = 8, h = 8;
      final rgba = <int>[];
      for (var i = 0; i < w * h; i++) {
        rgba.addAll(i < 8 ? [0, 0, 0, 255] : [255, 255, 255, 0]);
      }

      final png = await encodeRgbaToPng(rgba, w, h);
      final round = await SignaturePhotoSource.extract(png);

      // A JPEG preview would bring the paper back as black; PNG does not.
      expect(round.rgba[3], 255);
    });
  });
}
