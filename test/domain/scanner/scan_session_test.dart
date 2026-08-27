import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/scanner/scanned_page.dart';
import 'package:folio/features/scanner/scanner_providers.dart';

import 'jpeg_fixtures.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  ScanSession session() => container.read(scanSessionProvider.notifier);
  List<ScannedPage> pages() => container.read(scanSessionProvider);

  ScannedPage colour() => ScannedPage(kColourJpeg);
  ScannedPage grey() => ScannedPage(kGrayJpeg);

  test('starts empty', () => expect(pages(), isEmpty));

  test('captured pages arrive in order', () {
    session()
      ..add(colour())
      ..add(grey());

    expect(pages().map((p) => p.info.components), [3, 1]);
  });

  test('addAll appends a gallery selection without losing what is there', () {
    session()
      ..add(colour())
      ..addAll([grey(), grey()]);

    expect(pages(), hasLength(3));
    expect(pages().first.info.components, 3);
  });

  test('removing a page leaves the rest in order', () {
    session()
      ..addAll([colour(), grey(), colour()])
      ..removeAt(1);

    expect(pages().map((p) => p.info.components), [3, 3]);
  });

  group('move', () {
    test('moves a page later', () {
      session()
        ..addAll([colour(), grey(), grey()])
        ..move(0, 2);

      expect(pages().map((p) => p.info.components), [1, 1, 3]);
    });

    test('moves a page earlier', () {
      session()
        ..addAll([grey(), grey(), colour()])
        ..move(2, 0);

      expect(pages().map((p) => p.info.components), [3, 1, 1]);
    });

    // A no-op move must not drop or duplicate the page, which is what a naive
    // remove-then-insert gets wrong at the boundaries.
    test('moving a page onto itself changes nothing', () {
      session()
        ..addAll([colour(), grey()])
        ..move(1, 1);

      expect(pages().map((p) => p.info.components), [3, 1]);
    });

    test('the page count never changes', () {
      session().addAll([colour(), grey(), colour()]);

      for (final (from, to) in [(0, 2), (2, 0), (1, 2), (0, 1)]) {
        session().move(from, to);
        expect(pages(), hasLength(3));
      }
    });
  });

  test('clear discards everything captured', () {
    session()
      ..addAll([colour(), grey()])
      ..clear();

    expect(pages(), isEmpty);
  });
}
