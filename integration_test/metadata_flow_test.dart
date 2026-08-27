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
import 'package:folio/data/repositories/metadata_repository_impl.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
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
  late MetadataRepositoryImpl subject;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('meta_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = MetadataRepositoryImpl(
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

  group('editing document details', () {
    test('what is written is what reads back', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Details.pdf',
      );

      final saved = await subject.save(
        src.id,
        const PdfMetadata(
          title: 'Quarterly Report',
          author: 'A Person',
          subject: 'Numbers',
          keywords: 'quarterly, report',
        ),
      );

      final read = await subject.read(saved.id);

      expect(read.title, 'Quarterly Report');
      expect(read.author, 'A Person');
      expect(read.subject, 'Numbers');
      expect(read.keywords, 'quarterly, report');
    });

    // Existing details must be shown before they are edited, or the dialog
    // would silently erase whatever it did not display.
    test('existing details are read from a document that has them', () async {
      final src = await library.importFile(
        await fixturePath('with_metadata.pdf'),
        displayName: 'Existing.pdf',
      );

      final read = await subject.read(src.id);

      expect(read.title, 'FOLIO-PROBE-TITLE');
      expect(read.author, 'FOLIO-PROBE-AUTHOR');
    });

    test('editing one field keeps the others', () async {
      final src = await library.importFile(
        await fixturePath('with_metadata.pdf'),
        displayName: 'Partial.pdf',
      );
      final before = await subject.read(src.id);

      final saved = await subject.save(
        src.id,
        PdfMetadata(
          title: 'Renamed',
          author: before.author,
          subject: before.subject,
        ),
      );

      final read = await subject.read(saved.id);
      expect(read.title, 'Renamed');
      expect(read.author, 'FOLIO-PROBE-AUTHOR');
    });

    test('the document still opens and renders', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Renders.pdf',
      );

      final saved = await subject.save(
        src.id,
        const PdfMetadata(title: 'Still Fine'),
      );

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(saved)),
      );
      final pages = h.pageCount;
      final text = await engine.extractText(h, 0);
      await engine.close(h);

      expect(pages, 3);
      expect(text!.fullText, contains('Confidential'));
    });

    test('the source document is untouched', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Source.pdf',
      );
      final bytes = await File(
        await library.resolveReadablePath(src),
      ).readAsBytes();

      await subject.save(src.id, const PdfMetadata(title: 'New'));

      expect(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
        bytes,
      );
    });

    // Writing nothing would produce a duplicate document with no change in it.
    test('empty details are refused', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Empty.pdf',
      );

      await expectLater(
        subject.save(src.id, const PdfMetadata()),
        throwsArgumentError,
      );
    });
  });
}
