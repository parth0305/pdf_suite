import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/features/home/providers.dart';
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
  late LibraryRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('viewer_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Widget harness(LibraryDocument doc) => ProviderScope(
    overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ViewerScreen(document: doc),
    ),
  );

  group('viewer', () {
    testWidgets('renders a document and reports its page count', (
      tester,
    ) async {
      final doc = await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );

      await tester.pumpWidget(harness(doc));
      // Wait for the page indicator, which only exists once the document
      // has loaded. pumpAndSettle(Duration) is a pump INTERVAL, not a wait,
      // and the toolbar buttons stay disabled until the page count arrives.
      await pumpUntilFound(tester, find.text('1 of 3'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('invoice.pdf'), findsOneWidget);
    });

    testWidgets('opening a document records it as recent', (tester) async {
      final doc = await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );
      expect(await repo.recents(), isEmpty);

      await tester.pumpWidget(harness(doc));
      // Wait for the page indicator, which only exists once the document
      // has loaded. pumpAndSettle(Duration) is a pump INTERVAL, not a wait,
      // and the toolbar buttons stay disabled until the page count arrives.
      await pumpUntilFound(tester, find.text('1 of 3'));
      await tester.pumpAndSettle();

      expect(await repo.recents(), hasLength(1));
    });

    testWidgets(
      'a corrupt document shows a friendly message, not a stack trace',
      (tester) async {
        // Import bypasses the %PDF check by writing the managed copy directly,
        // so the failure surfaces from the engine rather than the importer.
        final doc = await repo.importFile(
          await fixturePath('corrupt_truncated.pdf'),
          displayName: 'broken.pdf',
        );

        await tester.pumpWidget(harness(doc));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // The viewer must not surface an exception widget.
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the search bar opens and closes', (tester) async {
      final doc = await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );

      await tester.pumpWidget(harness(doc));
      // Wait for the page indicator, which only exists once the document
      // has loaded. pumpAndSettle(Duration) is a pump INTERVAL, not a wait,
      // and the toolbar buttons stay disabled until the page count arrives.
      await pumpUntilFound(tester, find.text('1 of 3'));
      await tester.pumpAndSettle();

      // The search button stays disabled until the searcher exists, which is
      // later than the page count arriving.
      await pumpUntilEnabled(tester, Icons.search);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(find.text('Search in document'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Search in document'), findsNothing);
    });

    testWidgets('full screen hides the chrome and can be exited', (
      tester,
    ) async {
      final doc = await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );

      await tester.pumpWidget(harness(doc));
      // Wait for the page indicator, which only exists once the document
      // has loaded. pumpAndSettle(Duration) is a pump INTERVAL, not a wait,
      // and the toolbar buttons stay disabled until the page count arrives.
      await pumpUntilFound(tester, find.text('1 of 3'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.fullscreen));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

      await tester.tap(find.byIcon(Icons.fullscreen_exit));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
