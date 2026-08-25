import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:folio/engine/pdfrx_page_editor.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late PdfrxEngine engine;
  late PdfrxPageEditor editor;

  setUp(() {
    engine = PdfrxEngine();
    editor = PdfrxPageEditor(engine);
  });

  group('PdfrxPageEditor round-trips', () {
    // A write that "succeeded" proves nothing until something reads it back.
    test('reorder survives a round trip', () async {
      final doc = await engine.open(
        FileSource(await fixturePath('sample_3page.pdf')),
      );

      final bytes = await editor.materialise(
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 2),
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 0),
        ],
        sources: {1: doc},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'out.pdf'),
      );
      expect(reopened.pageCount, 2);

      final first = await engine.extractText(reopened, 0);
      expect(first!.fullText, contains('Appendix A'));

      await engine.close(reopened);
      await engine.close(doc);
    });

    test('merge combines two documents in order', () async {
      final a = await engine.open(
        FileSource(await fixturePath('sample_3page.pdf')),
      );
      final b = await engine.open(
        FileSource(await fixturePath('pages_10.pdf')),
      );

      final bytes = await editor.materialise(
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: 2, sourcePageIndex: 0),
          PageSlot(sourceDocumentId: 2, sourcePageIndex: 1),
        ],
        sources: {1: a, 2: b},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'merged.pdf'),
      );
      expect(reopened.pageCount, 3);

      final first = await engine.extractText(reopened, 0);
      expect(first!.fullText, contains('Confidential Invoice'));
      final second = await engine.extractText(reopened, 1);
      expect(second!.fullText, contains('Section 1'));

      await engine.close(reopened);
      await engine.close(a);
      await engine.close(b);
    });

    // Rotation must change the page geometry, not just a metadata flag.
    test('rotation survives and swaps page geometry', () async {
      final doc = await engine.open(
        FileSource(await fixturePath('sample_3page.pdf')),
      );

      final bytes = await editor.materialise(
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 0, quarterTurns: 1),
        ],
        sources: {1: doc},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'rot.pdf'),
      );
      final info = await engine.pageInfo(reopened, 0);

      expect(
        info.isLandscape,
        isTrue,
        reason: 'A4 portrait rotated 90 degrees',
      );
      expect(info.widthPt, closeTo(842, 1));
      expect(info.heightPt, closeTo(595, 1));

      await engine.close(reopened);
      await engine.close(doc);
    });

    test('duplicate produces two pages with the same content', () async {
      final doc = await engine.open(
        FileSource(await fixturePath('sample_3page.pdf')),
      );

      final bytes = await editor.materialise(
        slots: const [
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 2),
          PageSlot(sourceDocumentId: 1, sourcePageIndex: 2),
        ],
        sources: {1: doc},
      );

      final reopened = await engine.open(
        BytesSource(bytes, sourceName: 'dup.pdf'),
      );
      expect(reopened.pageCount, 2);

      final first = await engine.extractText(reopened, 0);
      final second = await engine.extractText(reopened, 1);
      expect(first!.fullText, second!.fullText);

      await engine.close(reopened);
      await engine.close(doc);
    });

    test('an empty slot list throws EmptyDocument', () async {
      await expectLater(
        editor.materialise(slots: const [], sources: const {}),
        throwsA(isA<EmptyDocument>()),
      );
    });

    test(
      'a 1000-page document materialises without exhausting memory',
      () async {
        final doc = await engine.open(
          FileSource(await fixturePath('pages_1000.pdf')),
        );

        final bytes = await editor.materialise(
          slots: [
            for (var i = 0; i < 1000; i++)
              PageSlot(sourceDocumentId: 1, sourcePageIndex: i),
          ],
          sources: {1: doc},
        );

        final reopened = await engine.open(
          BytesSource(bytes, sourceName: 'big.pdf'),
        );
        expect(reopened.pageCount, 1000);

        await engine.close(reopened);
        await engine.close(doc);
      },
    );
  });
}
