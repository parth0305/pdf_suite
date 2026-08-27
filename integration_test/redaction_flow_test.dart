@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/redaction_repository_impl.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/redaction/redaction_box.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/viewer/redaction_providers.dart';
import 'package:folio/features/viewer/viewer_screen.dart';
import 'package:folio/l10n/app_localizations.dart';
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
  late RedactionRepositoryImpl subject;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('redact_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = RedactionRepositoryImpl(
      library: library,
      documents: DocumentWriter(
        library: library,
        writer: SafeFileWriter(),
        libraryRoot: root,
      ),
      engine: PdfrxEngine(),
    );
    engine = PdfrxEngine();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<LibraryDocument> seed(String name) async => library.importFile(
    await fixturePath('sample_3page.pdf'),
    displayName: name,
  );

  Future<String> textOf(LibraryDocument d, int pageIndex) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final text = await engine.extractText(h, pageIndex);
    await engine.close(h);
    return text?.fullText ?? '';
  }

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

  /// Everything in the file a determined reader could get at: the raw bytes,
  /// plus every Flate stream inflated.
  ///
  /// Grepping the raw bytes alone proves nothing here - a redacted page's
  /// content stream is compressed, so ANY text in it is invisible to a plain
  /// search. That version of this assertion passed against a build that kept
  /// every redacted character.
  Future<String> recoverableText(LibraryDocument d) async {
    final raw = await File(await library.resolveReadablePath(d)).readAsBytes();
    final text = latin1.decode(raw, allowInvalid: true);
    final found = StringBuffer(text);

    for (final m in RegExp(
      r'/Length (\d+)[^>]*?/Filter /FlateDecode\s*>>\s*stream\r?\n',
    ).allMatches(text)) {
      final start = m.end;
      final length = int.parse(m.group(1)!);
      if (start + length > raw.length) continue;
      try {
        found.write(
          latin1.decode(
            ZLibCodec().decode(raw.sublist(start, start + length)),
            allowInvalid: true,
          ),
        );
      } on FormatException {
        // Not every match is a stream we can inflate; skip it rather than
        // fail the search.
        continue;
      }
    }

    return found.toString();
  }

  int diff(List<int> a, List<int> b) {
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) n++;
    }
    return n;
  }

  /// A box over the whole body line of page 1, which carries the token
  /// REDACT-ME-9931. Found from the character rects rather than guessed, so
  /// the test does not depend on the fixture's exact layout.
  Future<RedactionBox> boxOverToken(LibraryDocument d) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final text = (await engine.extractText(h, 0))!;
    await engine.close(h);

    final at = text.fullText.indexOf('REDACT-ME-9931');
    expect(at, greaterThanOrEqualTo(0), reason: 'fixture must carry the token');

    final rects = text.charRects.sublist(at, at + 'REDACT-ME-9931'.length);
    return RedactionBox(
      pageIndex: 0,
      rect: TextRect(
        left: rects.map((r) => r.left).reduce((a, b) => a < b ? a : b) - 1,
        right: rects.map((r) => r.right).reduce((a, b) => a > b ? a : b) + 1,
        top: rects.map((r) => r.top).reduce((a, b) => a > b ? a : b) + 1,
        bottom: rects.map((r) => r.bottom).reduce((a, b) => a < b ? a : b) - 1,
      ),
    );
  }

  group('redaction', () {
    // THE assertion. Extracting text is not enough on its own: a redaction
    // that merely hid the text would still pass an extraction check on some
    // readers. The raw bytes are what settle it.
    test(
      'the redacted token is gone from the text AND from the file',
      () async {
        final src = await seed('Redact.pdf');
        final out = await subject.apply(src.id, [await boxOverToken(src)]);

        expect(await textOf(out, 0), isNot(contains('REDACT-ME-9931')));
        expect(
          await recoverableText(out),
          isNot(contains('REDACT-ME-9931')),
          reason: 'gone from the file, not merely hidden inside a Flate stream',
        );
      },
    );

    // The inflating half of the assertion above, checked against the source
    // document. If this fails, `recoverableText` is not actually reaching
    // inside compressed streams and the assertion above proves nothing.
    test(
      'the search that finds it can see inside compressed streams',
      () async {
        final src = await seed('Premise.pdf');
        final out = await subject.apply(
          src.id,
          // A box in an empty corner, redacting nothing.
          [
            const RedactionBox(
              pageIndex: 0,
              rect: TextRect(left: 0, right: 1, top: 1, bottom: 0),
            ),
          ],
        );

        final raw = await File(
          await library.resolveReadablePath(out),
        ).readAsBytes();

        expect(
          latin1.decode(raw, allowInvalid: true),
          isNot(contains('REDACT-ME-9931')),
          reason: 'the premise: a plain byte search cannot see it',
        );
        expect(
          await recoverableText(out),
          contains('REDACT-ME-9931'),
          reason: 'but inflating the streams does',
        );
      },
    );

    // Without this the rebuild half could emit nothing at all and every
    // removal assertion above would still pass.
    test('text outside the box is still extractable', () async {
      final src = await seed('Survives.pdf');
      final out = await subject.apply(src.id, [await boxOverToken(src)]);

      expect(
        await textOf(out, 0),
        contains('Confidential'),
        reason: 'the page title is outside the box and must survive',
      );
    });

    test('the source document is untouched', () async {
      final src = await seed('Source.pdf');
      final before = await File(
        await library.resolveReadablePath(src),
      ).readAsBytes();

      await subject.apply(src.id, [await boxOverToken(src)]);

      expect(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
        before,
      );
    });

    test('pages without boxes render identically', () async {
      final src = await seed('Others.pdf');
      final before = await render(src, 2);

      final out = await subject.apply(src.id, [await boxOverToken(src)]);

      expect(diff(before, await render(out, 2)), 0);
    });

    // `diff() > n` would NOT do here: rasterising the page changes thousands
    // of pixels by itself, so that assertion passes against a build that
    // never paints a box at all. This samples the box's own centre.
    test('the redacted page shows a black box where the token was', () async {
      final src = await seed('Painted.pdf');
      final box = await boxOverToken(src);

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(src)),
      );
      final info = await engine.pageInfo(h, 0);
      await engine.close(h);

      final out = await subject.apply(src.id, [box]);
      final pixels = await render(out, 0);

      // PDF points to the 400x566 render, flipping the vertical axis.
      final cx = ((box.rect.left + box.rect.right) / 2 / info.widthPt * 400)
          .round();
      final cy =
          ((info.heightPt - (box.rect.top + box.rect.bottom) / 2) /
                  info.heightPt *
                  566)
              .round();
      final i = (cy * 400 + cx) * 4;

      expect(
        [pixels[i], pixels[i + 1], pixels[i + 2]],
        everyElement(lessThan(40)),
        reason: 'the box centre must be black, not merely different',
      );

      // And a point well outside it must not be.
      final outside = ((566 - 20) * 400 + 200) * 4;
      expect(
        pixels[outside] + pixels[outside + 1] + pixels[outside + 2],
        greaterThan(400),
        reason: 'the rest of the page is not blacked out',
      );
    });

    test('the result is a new document named for it', () async {
      final src = await seed('Named.pdf');
      final out = await subject.apply(src.id, [await boxOverToken(src)]);

      expect(out.id, isNot(src.id));
      expect(out.displayName, contains('redacted'));
    });

    test('no boxes is refused rather than silently copying', () async {
      final src = await seed('Empty.pdf');

      await expectLater(subject.apply(src.id, const []), throwsArgumentError);
    });
  });

  group('redact mode', () {
    Widget harness(LibraryDocument doc) => ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(library),
        redactionRepositoryProvider.overrideWithValue(subject),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ViewerScreen(document: doc),
      ),
    );

    testWidgets('drawing a box and applying it produces a document', (
      tester,
    ) async {
      final src = await seed('UiFlow.pdf');
      await tester.pumpWidget(harness(src));
      // The actions menu is a bottom sheet now, opened from a single
      // overflow button, with Redact under the "Protect" group.
      await pumpUntilEnabled(tester, Icons.more_horiz);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redact'));
      await tester.pumpAndSettle();

      // Apply is disabled until a box exists: an empty redaction would write
      // a new document identical to the original.
      final apply = find.widgetWithText(FilledButton, 'Apply redactions');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      // Drag a box across the middle of the page.
      final centre = tester.getCenter(find.byType(PdfViewer));
      await tester.dragFrom(
        centre - const Offset(90, 20),
        const Offset(180, 40),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(apply).onPressed,
        isNotNull,
        reason: 'a drawn box enables Apply',
      );

      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Redact'));

      await pumpUntilAsync(
        tester,
        () async => (await library.all()).any(
          (d) => d.displayName.contains('redacted'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (await library.all()).where((d) => d.displayName.contains('redacted')),
        hasLength(1),
      );
    });

    testWidgets('the confirmation names what is not covered', (tester) async {
      final src = await seed('UiWarn.pdf');
      await tester.pumpWidget(harness(src));
      // The actions menu is a bottom sheet now, opened from a single
      // overflow button, with Redact under the "Protect" group.
      await pumpUntilEnabled(tester, Icons.more_horiz);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redact'));
      await tester.pumpAndSettle();

      final centre = tester.getCenter(find.byType(PdfViewer));
      await tester.dragFrom(
        centre - const Offset(90, 20),
        const Offset(180, 40),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Apply redactions'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not covered'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        (await library.all()).where((d) => d.displayName.contains('redacted')),
        isEmpty,
        reason: 'cancelling must write nothing',
      );
    });
  });
}
