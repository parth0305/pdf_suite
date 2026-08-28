@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/office_export_repository_impl.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/office_export_repository.dart';
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
  late OfficeExportRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('office_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = OfficeExportRepositoryImpl(
      library: library,
      engine: PdfrxEngine(),
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<LibraryDocument> seed(String fixture, String name) async =>
      library.importFile(await fixturePath(fixture), displayName: name);

  /// The bytes of one file inside the archive, found through the central
  /// directory the way any reader does.
  ///
  /// A reader of my own rather than a package: what is being checked is that
  /// the archive is readable at all, and the ZIP tests already hand the same
  /// writer's output to Python for a second opinion.
  String partOf(List<int> bytes, String name) {
    int u16(int at) => bytes[at] | (bytes[at + 1] << 8);
    int u32(int at) =>
        bytes[at] |
        (bytes[at + 1] << 8) |
        (bytes[at + 2] << 16) |
        (bytes[at + 3] << 24);

    var eocd = bytes.length - 22;
    while (eocd >= 0 && u32(eocd) != 0x06054b50) {
      eocd--;
    }
    if (eocd < 0) throw StateError('not an archive');

    var at = u32(eocd + 16);
    for (var i = 0; i < u16(eocd + 10); i++) {
      final nameLength = u16(at + 28);
      final found = latin1.decode(bytes.sublist(at + 46, at + 46 + nameLength));

      if (found == name) {
        final localAt = u32(at + 42);
        final start = localAt + 30 + u16(localAt + 26) + u16(localAt + 28);
        final data = bytes.sublist(start, start + u32(localAt + 18));

        return utf8.decode(
          u16(localAt + 8) == 0 ? data : ZLibCodec(raw: true).decode(data),
          allowMalformed: true,
        );
      }

      at += 46 + nameLength + u16(at + 30) + u16(at + 32);
    }

    throw StateError('no part $name');
  }

  Future<List<int>> convert(LibraryDocument doc, OfficeFormat format) async {
    final exported = await subject.export(doc.id, format);
    return File(exported.path).readAsBytes();
  }

  group('converting to Office', () {
    test('a document with text has text to convert', () async {
      final src = await seed('sample_3page.pdf', 'Text.pdf');

      expect(await subject.hasText(src.id), isTrue);
    });

    // A scan has none until it has been through OCR. A Word document with
    // nothing in it is a worse answer than saying so first.
    test('a scan has none until it has been read', () async {
      final src = await seed('scanned_no_text.pdf', 'Scan.pdf');

      expect(await subject.hasText(src.id), isFalse);
    });

    group('word', () {
      test('the page text arrives in the document', () async {
        final src = await seed('sample_3page.pdf', 'Word.pdf');
        final document = partOf(
          await convert(src, OfficeFormat.word),
          'word/document.xml',
        );

        expect(document, contains('Confidential Invoice'));
        expect(document, contains('PLATYPUS-TOKEN-42'));
      });

      test('every page is there, separated by page breaks', () async {
        final src = await seed('sample_3page.pdf', 'Pages.pdf');
        final document = partOf(
          await convert(src, OfficeFormat.word),
          'word/document.xml',
        );

        expect(document, contains('Terms and Conditions'));
        expect(document, contains('Appendix A'));
        expect('w:type="page"'.allMatches(document).length, 2);
      });

      test('the text is split into more than one paragraph', () async {
        final src = await seed('sample_3page.pdf', 'Paras.pdf');
        final document = partOf(
          await convert(src, OfficeFormat.word),
          'word/document.xml',
        );

        expect('<w:p>'.allMatches(document).length, greaterThan(3));
      });

      test('the file is named after the document', () async {
        final src = await seed('sample_3page.pdf', 'Report.pdf');
        final exported = await subject.export(src.id, OfficeFormat.word);

        expect(exported.name, 'Report.docx');
      });

      test('the source document is untouched', () async {
        final src = await seed('sample_3page.pdf', 'Source.pdf');
        final before = await File(
          await library.resolveReadablePath(src),
        ).readAsBytes();

        await convert(src, OfficeFormat.word);

        expect(
          await File(await library.resolveReadablePath(src)).readAsBytes(),
          before,
        );
      });
    });

    group('excel', () {
      test('each page becomes a sheet', () async {
        final src = await seed('sample_3page.pdf', 'Book.pdf');
        final bytes = await convert(src, OfficeFormat.excel);

        expect(partOf(bytes, 'xl/workbook.xml'), contains('name="Page 3"'));
      });

      test('the text arrives in cells', () async {
        final src = await seed('sample_3page.pdf', 'Cells.pdf');
        final sheet = partOf(
          await convert(src, OfficeFormat.excel),
          'xl/worksheets/sheet1.xml',
        );

        expect(sheet, contains('Confidential Invoice'));
        expect(sheet, contains('r="A1"'));
      });
    });

    group('powerpoint', () {
      test('each page becomes a slide', () async {
        final src = await seed('sample_3page.pdf', 'Deck.pdf');
        final bytes = await convert(src, OfficeFormat.powerPoint);

        expect(partOf(bytes, 'ppt/slides/slide3.xml'), contains('Appendix A'));
      });

      test('the presentation lists every slide', () async {
        final src = await seed('sample_3page.pdf', 'List.pdf');
        final presentation = partOf(
          await convert(src, OfficeFormat.powerPoint),
          'ppt/presentation.xml',
        );

        expect('<p:sldId '.allMatches(presentation).length, 3);
      });
    });
  });
}
