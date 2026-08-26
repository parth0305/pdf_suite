import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/pdf/pdf_encryption_aes.dart';

/// Deterministic bytes, so every value below is reproducible.
List<int> fakeRandom(int count) => List<int>.generate(count, (i) => i & 0xFF);

void main() {
  group('hash2B', () {
    test('is 32 bytes and deterministic', () {
      final a = hash2B(utf8.encode('folio'), fakeRandom(8), const []);
      final b = hash2B(utf8.encode('folio'), fakeRandom(8), const []);

      expect(a, hasLength(32));
      expect(a, b);
    });

    test('a different password gives a different hash', () {
      expect(
        hash2B(utf8.encode('folio'), fakeRandom(8), const []),
        isNot(hash2B(utf8.encode('folio2'), fakeRandom(8), const [])),
      );
    });

    test('a different salt gives a different hash', () {
      expect(
        hash2B(utf8.encode('folio'), fakeRandom(8), const []),
        isNot(hash2B(utf8.encode('folio'), List.filled(8, 9), const [])),
      );
    });
  });

  group('buildAesValues', () {
    final values = buildAesValues(
      password: 'folio-test',
      permissions: -44,
      randomBytes: fakeRandom,
    );

    // The widths are fixed by ISO 32000-2. A wrong one produces a document
    // nothing can open, with no clue as to why.
    test('every value has the width the specification requires', () {
      expect(values.fileKey, hasLength(32));
      expect(values.u, hasLength(48));
      expect(values.ue, hasLength(32));
      expect(values.o, hasLength(48));
      expect(values.oe, hasLength(32));
      expect(values.perms, hasLength(16));
    });

    test('the file key does not appear in any published value', () {
      final key = values.fileKey.join(',');
      for (final published in [values.u, values.o, values.perms]) {
        expect(published.join(','), isNot(contains(key)));
      }
    });
  });

  group('aesEncrypt', () {
    final key = List<int>.generate(32, (i) => i);

    test('prepends the IV and pads to a block boundary', () {
      final out = aesEncrypt(key, utf8.encode('hello'), fakeRandom(16));

      expect(out.length % 16, 0);
      expect(out.take(16), fakeRandom(16), reason: 'the IV comes first');
      expect(out.length, greaterThan(16));
    });

    // A render test can NEVER catch IV reuse: a repeated IV still decrypts
    // correctly. It is a cryptographic weakness, not a functional bug, so it
    // has to be observed here - identical plaintext must not produce
    // identical ciphertext.
    test('the same plaintext encrypts differently each time', () {
      var counter = 0;
      List<int> changingIv(int n) =>
          List<int>.generate(n, (i) => (i + counter++) & 0xFF);

      final first = aesEncrypt(key, utf8.encode('same'), changingIv(16));
      final second = aesEncrypt(key, utf8.encode('same'), changingIv(16));

      expect(first, isNot(second));
    });
  });
}
