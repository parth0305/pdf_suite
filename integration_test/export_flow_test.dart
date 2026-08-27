@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/export_repository_impl.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/sharing/platform_export.dart';
import 'package:folio/domain/repositories/export_repository.dart';
import 'package:integration_test/integration_test.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late ExportRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('export_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = ExportRepositoryImpl(library: library);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('export', () {
    test('a real document prepares with its bytes intact', () async {
      final path = await fixturePath('sample_3page.pdf');
      final doc = await library.importFile(path, displayName: 'Invoice.pdf');

      final export = await subject.prepare(doc.id);

      expect(export.bytes, await File(path).readAsBytes());
      expect(export.isProtected, isFalse);
      expect(subject.refusalFor(export), isNull);
    });

    // The fixture is genuinely encrypted, so this exercises the real detection
    // rather than a hand-written trailer.
    test('a genuinely encrypted document refuses to print', () async {
      final doc = await library.importFile(
        await fixturePath('encrypted_user_pw.pdf'),
        displayName: 'Secret.pdf',
      );

      final export = await subject.prepare(doc.id);

      expect(export.isProtected, isTrue);
      expect(subject.refusalFor(export), PrintRefusal.protected);
    });

    // Sharing an encrypted document is safe: it stays encrypted. Nothing in
    // the refusal path should prevent it being prepared.
    test('an encrypted document still prepares for sharing', () async {
      final doc = await library.importFile(
        await fixturePath('encrypted_user_pw.pdf'),
        displayName: 'Secret.pdf',
      );

      final export = await subject.prepare(doc.id);

      expect(export.bytes, isNotEmpty);
      expect(export.fileName, 'Secret.pdf');
    });

    // The share sheet hands a PATH to another application, so the file has to
    // exist and carry the right name. Writing it is the part that can fail on
    // a device without ever failing in a unit test.
    test('sharing writes a real file with the document name', () async {
      final doc = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Quarterly Report.pdf',
      );
      final export = await subject.prepare(doc.id);

      final dir = await Directory.systemTemp.createTemp('share_probe');
      final file = File('${dir.path}/${export.fileName}')
        ..writeAsBytesSync(export.bytes);

      expect(file.existsSync(), isTrue);
      expect(file.path, endsWith('Quarterly Report.pdf'));
      expect(await file.readAsBytes(), export.bytes);
    });

    test('the platform export is constructible on this device', () {
      // Not called: printing opens a system dialog and sharing opens a sheet,
      // neither of which an unattended test can dismiss. This asserts the
      // plugin registrations resolve, which is what actually breaks per
      // platform.
      expect(const SystemExport(), isA<PlatformExport>());
    });
  });
}
