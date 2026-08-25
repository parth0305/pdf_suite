import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/engine/pdf_engine.dart';

import '../../fakes/fake_pdf_engine.dart';

void main() {
  group('FakePdfEngine', () {
    test('opens a document and reports its page count', () async {
      final engine = FakePdfEngine()
        ..addDocument('a.pdf', pages: ['Hello world', 'Second page']);

      final doc = await engine.open(const FileSource('a.pdf'));
      expect(doc.pageCount, 2);
    });

    test('extracts text with one rect per character', () async {
      final engine = FakePdfEngine()..addDocument('a.pdf', pages: ['abc']);
      final doc = await engine.open(const FileSource('a.pdf'));

      final text = await engine.extractText(doc, 0);
      expect(text!.fullText, 'abc');
      expect(text.charRects, hasLength(3));
    });

    test('throws DocumentCorrupt for an unknown document', () async {
      final engine = FakePdfEngine();
      await expectLater(
        engine.open(const FileSource('missing.pdf')),
        throwsA(isA<DocumentCorrupt>()),
      );
    });

    test('requests a password for an encrypted document', () async {
      final engine = FakePdfEngine()
        ..addDocument('locked.pdf', pages: ['secret'], password: 'hunter2');

      var asked = false;
      final doc = await engine.open(
        const FileSource('locked.pdf'),
        onPasswordRequired: () async {
          asked = true;
          return 'hunter2';
        },
      );

      expect(asked, isTrue);
      expect(doc.pageCount, 1);
    });

    test(
      'throws WrongPassword when the supplied password is incorrect',
      () async {
        final engine = FakePdfEngine()
          ..addDocument('locked.pdf', pages: ['secret'], password: 'hunter2');

        await expectLater(
          engine.open(
            const FileSource('locked.pdf'),
            onPasswordRequired: () async => 'wrong',
          ),
          throwsA(isA<WrongPassword>()),
        );
      },
    );

    test('throws PasswordRequired when the user cancels', () async {
      final engine = FakePdfEngine()
        ..addDocument('locked.pdf', pages: ['secret'], password: 'hunter2');

      await expectLater(
        engine.open(
          const FileSource('locked.pdf'),
          onPasswordRequired: () async => null,
        ),
        throwsA(isA<PasswordRequired>()),
      );
    });

    test('renders a page of the requested pixel size', () async {
      final engine = FakePdfEngine()..addDocument('a.pdf', pages: ['x']);
      final doc = await engine.open(const FileSource('a.pdf'));

      final img = await engine.renderPage(
        doc,
        0,
        targetWidthPx: 100,
        targetHeightPx: 141,
      );
      expect(img.widthPx, 100);
      expect(img.heightPx, 141);
      expect(img.bgraPixels, hasLength(100 * 141 * 4));
    });

    test('a closed handle can no longer be used', () async {
      final engine = FakePdfEngine()..addDocument('a.pdf', pages: ['x']);
      final doc = await engine.open(const FileSource('a.pdf'));
      await engine.close(doc);

      await expectLater(
        engine.pageInfo(doc, 0),
        throwsA(isA<UnknownFailure>()),
      );
    });
  });
}
