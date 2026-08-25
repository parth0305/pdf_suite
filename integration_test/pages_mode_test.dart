import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/page_operations_repository_impl.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:folio/engine/pdfrx_page_editor.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/pages/providers.dart';
import 'package:folio/features/viewer/viewer_screen.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late PageOperationsRepositoryImpl ops;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pages_mode');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    engine = PdfrxEngine();
    ops = PageOperationsRepositoryImpl(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: root,
      editor: PdfrxPageEditor(engine),
      openSource: (doc) async =>
          engine.open(FileSource(await library.resolveReadablePath(doc))),
      closeSource: engine.close,
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Widget harness(LibraryDocument doc) => ProviderScope(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(library),
      pageOperationsRepositoryProvider.overrideWithValue(ops),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ViewerScreen(document: doc),
    ),
  );

  Future<LibraryDocument> seed() async => library.importFile(
    await fixturePath('sample_3page.pdf'),
    displayName: 'Invoice.pdf',
  );

  group('pages mode', () {
    testWidgets('shows one row per page', (tester) async {
      await tester.pumpWidget(harness(await seed()));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byIcon(Icons.dashboard_customize));
      await tester.pumpAndSettle();

      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 3'), findsOneWidget);
    });

    testWidgets('selecting a page enables the operations', (tester) async {
      await tester.pumpWidget(harness(await seed()));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.tap(find.byIcon(Icons.dashboard_customize));
      await tester.pumpAndSettle();

      // Delete is disabled with nothing selected.
      var deleteButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.delete_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(deleteButton.onPressed, isNull);

      await tester.tap(find.text('Page 1'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      deleteButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.delete_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(deleteButton.onPressed, isNotNull);
    });

    testWidgets('deleting a page removes its row, and undo restores it', (
      tester,
    ) async {
      await tester.pumpWidget(harness(await seed()));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.tap(find.byIcon(Icons.dashboard_customize));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Page 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Page 3'), findsNothing);

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pumpAndSettle();
      expect(find.text('Page 3'), findsOneWidget);
    });

    testWidgets('applying writes a new document and leaves the source alone', (
      tester,
    ) async {
      final doc = await seed();
      final sourcePath = await library.resolveReadablePath(doc);
      final sourceBytes = await File(sourcePath).readAsBytes();

      await tester.pumpWidget(harness(doc));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.tap(find.byIcon(Icons.dashboard_customize));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Page 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as new document'));

      // pumpAndSettle's argument is the pump interval, not a wait, so it can
      // return while the write is still in flight. Poll for the result, and
      // surface any error snackbar if one appeared instead.
      List<LibraryDocument> all = const [];
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        all = await library.all();
        if (all.length >= 2) break;
      }

      if (all.length < 2) {
        final snack = find.byType(SnackBar);
        if (snack.evaluate().isNotEmpty) {
          final text = find.descendant(of: snack, matching: find.byType(Text));
          fail(
            'apply did not create a document; UI showed: '
            '${text.evaluate().map((e) => (e.widget as Text).data).join(" | ")}',
          );
        }
      }

      expect(all, hasLength(2));
      expect(all.any((d) => d.displayName == 'Invoice (edited).pdf'), isTrue);
      expect(
        await File(sourcePath).readAsBytes(),
        sourceBytes,
        reason: 'the source document must be byte-identical afterwards',
      );
    });

    testWidgets('deleting every page is refused', (tester) async {
      await tester.pumpWidget(harness(await seed()));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.tap(find.byIcon(Icons.dashboard_customize));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(
        find.text('Page 1'),
        findsOneWidget,
        reason: 'a document must keep at least one page',
      );
    });
  });
}
