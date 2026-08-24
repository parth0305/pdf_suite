import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/features/home/library_screen.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/native.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lib_flow');
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

  Widget harness() => ProviderScope(
    overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LibraryScreen(),
    ),
  );

  group('library flow', () {
    testWidgets('an empty library shows the onboarding state', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('Import PDF'), findsOneWidget);
    });

    testWidgets('an imported document appears in the list', (tester) async {
      await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('No documents yet'), findsNothing);
      expect(find.textContaining('Imported copy'), findsOneWidget);
    });

    testWidgets('search filters the list and clearing restores it', (
      tester,
    ) async {
      final path = await fixturePath('sample_3page.pdf');
      await repo.importFile(path, displayName: 'invoice.pdf');
      await repo.importFile(path, displayName: 'contract.pdf');

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('contract.pdf'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'invo');
      await tester.pumpAndSettle();
      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('contract.pdf'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      expect(find.text('contract.pdf'), findsOneWidget);
    });

    testWidgets('a search with no matches shows the no-results state', (
      tester,
    ) async {
      await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('No documents match your search.'), findsOneWidget);
    });

    testWidgets('starring a document moves it into Favorites', (tester) async {
      await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.star_border).first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);

      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('invoice.pdf'), findsOneWidget);
    });

    testWidgets('an unstarred document does not appear in Favorites', (
      tester,
    ) async {
      await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();

      expect(find.text('invoice.pdf'), findsNothing);
      expect(find.text('Star a document to keep it here.'), findsOneWidget);
    });

    testWidgets('Recent is empty until a document is opened', (tester) async {
      await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();
      expect(find.text('Documents you open will appear here.'), findsOneWidget);
    });

    testWidgets('deleting removes the document from the list', (tester) async {
      await repo.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'invoice.pdf',
      );
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('invoice.pdf'), findsNothing);
      expect(find.text('No documents yet'), findsOneWidget);
    });
  });
}
