import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/scanner/image_source.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/scanner_repository.dart';
import 'package:folio/domain/scanner/scanned_page.dart';
import 'package:folio/features/scanner/scanner_providers.dart';
import 'package:folio/features/scanner/scanner_screen.dart';
import 'package:folio/l10n/app_localizations.dart';

import '../domain/scanner/jpeg_fixtures.dart';

/// Hands back fixed bytes, so the scanner's own behaviour is testable without
/// a camera. This boundary is the reason the feature has tests at all.
class FakeImageSource implements ScanImageSource {
  FakeImageSource({this.shot, this.gallery = const []});

  final List<int>? shot;
  final List<List<int>> gallery;
  int captures = 0;

  @override
  Future<List<int>?> capture() async {
    captures++;
    return shot;
  }

  @override
  Future<List<List<int>>> pickFromGallery() async => gallery;
}

class FakeScannerRepository implements ScannerRepository {
  List<ScannedPage>? saved;

  @override
  Future<LibraryDocument> save(List<ScannedPage> pages, {String? name}) async {
    saved = pages;
    return LibraryDocument(
      id: 1,
      ref: const ManagedRef(relativePath: 'a/b.pdf', contentHash: 'hash'),
      displayName: name ?? 'Scan.pdf',
      sizeBytes: 10,
      pageCount: pages.length,
      addedAt: DateTime(2026),
      isFavorite: false,
    );
  }
}

void main() {
  late FakeImageSource source;
  late FakeScannerRepository repo;

  setUp(() {
    source = FakeImageSource(shot: kColourJpeg);
    repo = FakeScannerRepository();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scanImageSourceProvider.overrideWithValue(source),
          scannerRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ScannerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Folio now produces documents with no text layer. Saying so costs one line;
  // discovering it after scanning a contract costs considerably more.
  testWidgets('warns that a scan has no text layer', (tester) async {
    await pump(tester);

    expect(find.textContaining('no text layer'), findsOneWidget);
    expect(find.textContaining('cannot be searched'), findsOneWidget);
  });

  testWidgets('save is disabled until a page exists', (tester) async {
    await pump(tester);

    final save = find.widgetWithText(FilledButton, 'Save as PDF');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Camera'));
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('a captured page is listed with its real dimensions', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Camera'));
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('64 x 64'), findsOneWidget);
  });

  testWidgets('backing out of the camera adds nothing', (tester) async {
    source = FakeImageSource();
    await pump(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Camera'));
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsNothing);
    expect(source.captures, 1, reason: 'the camera was opened');
  });

  testWidgets('importing adds every image chosen', (tester) async {
    source = FakeImageSource(gallery: [kColourJpeg, kGrayJpeg]);
    await pump(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Import images'));
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
  });

  // An image the PDF cannot carry must be refused when it is added, not at
  // save time - by then there may be ten more pages and no clue which one.
  testWidgets('an unsupported image is refused with a message', (tester) async {
    source = FakeImageSource(shot: const [0x89, 0x50, 0x4E, 0x47]);
    await pump(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Camera'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not a baseline JPEG'), findsOneWidget);
    expect(find.text('Page 1'), findsNothing);
  });

  testWidgets('a page can be removed', (tester) async {
    source = FakeImageSource(gallery: [kColourJpeg, kGrayJpeg]);
    await pump(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import images'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('Page 2'), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('saving hands the repository the captured pages', (tester) async {
    source = FakeImageSource(gallery: [kColourJpeg, kGrayJpeg]);
    await pump(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import images'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save as PDF'));
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(2));
    expect(repo.saved!.first.info.components, 3);
    expect(repo.saved!.last.info.components, 1);
  });
}
