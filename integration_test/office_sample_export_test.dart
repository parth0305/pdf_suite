@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/office_export_repository_impl.dart';
import 'package:folio/domain/repositories/office_export_repository.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../scripts/pdf_fixture_builder.dart';

/// Converts a real document and prints where the three files ended up, so they
/// can be opened in Word, Excel and PowerPoint themselves.
///
/// Deliberately NOT in `all_tests.dart`: it exists to be run by hand when the
/// question is whether Office accepts what Folio writes. The files stay inside
/// the app's own storage - a sandboxed app cannot write anywhere else - and
/// the printed paths are how they are collected afterwards.
///
///     flutter test integration_test/office_sample_export_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  test('convert a real document, and say where it went', () async {
    final root = await Directory.systemTemp.createTemp('office_sample');
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    try {
      final library = LibraryRepositoryImpl(
        dao: LibraryDao(db),
        writer: SafeFileWriter(),
        libraryRoot: root,
      );
      final office = OfficeExportRepositoryImpl(
        library: library,
        engine: PdfrxEngine(),
      );

      final source = File('${root.path}/sample.pdf');
      await source.writeAsBytes(buildPdf(kSampleThreePage), flush: true);

      final document = await library.importFile(
        source.path,
        displayName: 'Folio conversion.pdf',
      );

      for (final format in OfficeFormat.values) {
        final exported = await office.export(document.id, format);

        expect(File(exported.path).existsSync(), isTrue);
        // ignore: avoid_print
        print(
          'WROTE ${exported.path} '
          '${await File(exported.path).length()} bytes',
        );
      }
    } finally {
      await db.close();
    }
  });
}
