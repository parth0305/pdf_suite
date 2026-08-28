@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/image_export_repository_impl.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/signature/signature_photo_source.dart';
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
  late ImageExportRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('img_export');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = ImageExportRepositoryImpl(
      library: library,
      engine: PdfrxEngine(),
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<int> seed(String name) async => (await library.importFile(
    await fixturePath('sample_3page.pdf'),
    displayName: name,
  )).id;

  group('exporting pages as images', () {
    test('every page becomes a real file', () async {
      final pages = await subject.export(
        documentId: await seed('All.pdf'),
        range: '',
        dpi: 96,
      );

      expect(pages, hasLength(3));
      for (final page in pages) {
        expect(File(page.path).existsSync(), isTrue);
        expect(File(page.path).lengthSync(), greaterThan(0));
      }
    });

    test('a range exports only those pages', () async {
      final pages = await subject.export(
        documentId: await seed('Range.pdf'),
        range: '2-3',
        dpi: 96,
      );

      expect(pages.map((p) => p.pageNumber), [2, 3]);
    });

    // The decisive one: the file has to be a PNG a reader can decode, and it
    // has to show the page. A zero-byte file passes an existence check.
    test('the file decodes and shows the page', () async {
      final pages = await subject.export(
        documentId: await seed('Decode.pdf'),
        range: '1',
        dpi: 96,
      );

      final decoded = await decodeRgba(
        await File(pages.single.path).readAsBytes(),
      );

      // A4 at 96 DPI is 793x1123.
      expect(decoded.width, closeTo(793, 2));
      expect(decoded.height, closeTo(1123, 2));

      // The fixture is dark text on white: there must be some ink.
      var dark = 0;
      for (var i = 0; i < decoded.rgba.length; i += 4) {
        if (decoded.rgba[i] < 128) dark++;
      }
      expect(dark, greaterThan(100), reason: 'the page is not blank');
    });

    // Higher detail must actually mean more pixels, or the setting is a lie.
    test('the resolution setting changes the image size', () async {
      final id = await seed('Dpi.pdf');

      final low = await decodeRgba(
        await File(
          (await subject.export(
            documentId: id,
            range: '1',
            dpi: 96,
          )).single.path,
        ).readAsBytes(),
      );
      final high = await decodeRgba(
        await File(
          (await subject.export(
            documentId: id,
            range: '1',
            dpi: 300,
          )).single.path,
        ).readAsBytes(),
      );

      expect(high.width, greaterThan(low.width * 2));
    });

    test('the source document is untouched', () async {
      final id = await seed('Source.pdf');
      final doc = (await library.all()).firstWhere((d) => d.id == id);
      final before = await File(
        await library.resolveReadablePath(doc),
      ).readAsBytes();

      await subject.export(documentId: id, range: '', dpi: 96);

      expect(
        await File(await library.resolveReadablePath(doc)).readAsBytes(),
        before,
      );
    });

    test('the images go outside the library', () async {
      final pages = await subject.export(
        documentId: await seed('Outside.pdf'),
        range: '1',
        dpi: 96,
      );

      expect(
        pages.single.path,
        isNot(contains(root.path)),
        reason: 'the library holds documents, not pictures on their way out',
      );
    });
  });
}
