@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/archive_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/archive/pdfa_check.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/models/library_document.dart';
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
  late ArchiveRepositoryImpl subject;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('archive_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = ArchiveRepositoryImpl(
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

  Future<LibraryDocument> seed(String fixture, String name) async =>
      library.importFile(await fixturePath(fixture), displayName: name);

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

  group('archiving', () {
    // The generated sample uses Helvetica without carrying it, which is the
    // commonest reason a real document cannot be archived.
    test('a document naming a font it does not carry is refused', () async {
      final src = await seed('sample_3page.pdf', 'Fonts.pdf');
      final report = await subject.check(src.id);

      expect(report.canConvert, isFalse);
      expect(report.blockers[PdfaIssue.fontNotEmbedded], contains('Helvetica'));
      expect(subject.convert(src.id), throwsA(isA<UnsupportedPdfStructure>()));
    });

    // A scan carries no fonts, which is exactly why scanned documents are
    // what an archival format is usually wanted for.
    test('a document with no text converts', () async {
      final src = await seed('scanned_no_text.pdf', 'Scan.pdf');

      expect((await subject.check(src.id)).canConvert, isTrue);

      final out = await subject.convert(src.id);

      expect(out.displayName, contains('PDF/A'));
    });

    test('the converted document still opens and renders the same', () async {
      final src = await seed('scanned_no_text.pdf', 'Same.pdf');
      final before = await render(src, 0);

      final out = await subject.convert(src.id);

      expect(diff(before, await render(out, 0)), 0);
    });

    test('every page survives', () async {
      final src = await seed('scanned_no_text.pdf', 'Pages.pdf');
      final out = await subject.convert(src.id);

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final pages = h.pageCount;
      await engine.close(h);

      expect(pages, 3);
    });

    // The identification a validator reads, reached the way a reader reaches
    // it: trailer, root, catalogue, and only then the objects. An output
    // intent that is IN the file but not referenced from the catalogue is not
    // an output intent at all - and a plain text search cannot tell.
    test('the catalogue leads to the PDF/A declaration', () async {
      final src = await seed('scanned_no_text.pdf', 'Declared.pdf');
      final out = await subject.convert(src.id);

      final text = latin1.decode(
        await File(await library.resolveReadablePath(out)).readAsBytes(),
        allowInvalid: true,
      );

      String object(int number) => RegExp(
        '(?<![0-9])$number 0 obj(.*?)endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      final root = int.parse(
        RegExp(r'/Root\s+(\d+)\s+\d+\s+R').allMatches(text).last.group(1)!,
      );
      final catalogue = object(root);

      final intent = int.parse(
        RegExp(
          r'/OutputIntents\s*\[\s*(\d+)\s+\d+\s+R',
        ).firstMatch(catalogue)!.group(1)!,
      );
      expect(object(intent), contains('/GTS_PDFA1'));

      final metadata = int.parse(
        RegExp(r'/Metadata\s+(\d+)\s+\d+\s+R').firstMatch(catalogue)!.group(1)!,
      );
      final packet = object(metadata);

      expect(packet, contains('<pdfaid:part>2</pdfaid:part>'));
      expect(packet, contains('<pdfaid:conformance>B</pdfaid:conformance>'));
    });

    test('the colour profile is really in the file', () async {
      final src = await seed('scanned_no_text.pdf', 'Profile.pdf');
      final out = await subject.convert(src.id);

      final bytes = await File(
        await library.resolveReadablePath(out),
      ).readAsBytes();
      final text = latin1.decode(bytes, allowInvalid: true);

      // 'acsp' at offset 36 of the profile is the ICC file signature.
      final at = text.indexOf('acsp');
      expect(at, greaterThan(0));
      expect(
        bytes.sublist(at - 36, at - 32),
        // The profile's first four bytes are its own declared size.
        isNot([0, 0, 0, 0]),
      );
    });

    test('embedded JavaScript does not survive archiving', () async {
      final src = await seed('embedded_javascript.pdf', 'Script.pdf');
      final report = await subject.check(src.id);

      // The sample also names a font, so it cannot convert - but the check
      // still has to see the script, or conversion would keep it.
      expect(report.removals, contains(PdfaIssue.javaScript));
    });

    test('the source document is untouched', () async {
      final src = await seed('scanned_no_text.pdf', 'Source.pdf');
      final bytes = await File(
        await library.resolveReadablePath(src),
      ).readAsBytes();

      await subject.convert(src.id);

      expect(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
        bytes,
      );
    });
  });
}
