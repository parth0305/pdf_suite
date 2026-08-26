import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:folio/domain/pdf/pdf_encryption.dart';
import 'package:folio/domain/pdf/pdf_encryption_dictionary.dart';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

void main() {
  // Published RC4 test vectors. A cipher that merely "runs" proves nothing;
  // these are the only evidence the implementation is actually RC4.
  group('rc4 against known vectors', () {
    test('Key / Plaintext', () {
      expect(
        hex(rc4(latin1.encode('Key'), latin1.encode('Plaintext'))),
        'BBF316E8D940AF0AD3',
      );
    });

    test('Wiki / pedia', () {
      expect(
        hex(rc4(latin1.encode('Wiki'), latin1.encode('pedia'))),
        '1021BF0420',
      );
    });

    test('Secret / Attack at dawn', () {
      expect(
        hex(rc4(latin1.encode('Secret'), latin1.encode('Attack at dawn'))),
        '45A01F645FC35B383552544B9BF5',
      );
    });

    test('is its own inverse', () {
      final key = latin1.encode('folio-test');
      final plain = latin1.encode('the quick brown fox');
      expect(rc4(key, rc4(key, plain)), plain);
    });
  });

  group('padPassword', () {
    test('pads a short password to exactly 32 bytes', () {
      final padded = padPassword('abc');
      expect(padded, hasLength(32));
      expect(padded.take(3), latin1.encode('abc'));
      // Remainder comes from the standard padding string.
      expect(padded[3], kPadding[0]);
    });

    test('an empty password is entirely the padding string', () {
      expect(padPassword(''), kPadding);
    });

    test('truncates a password longer than 32 bytes', () {
      expect(padPassword('x' * 40), hasLength(32));
    });
  });

  group('encryption key derivation', () {
    test('is deterministic for the same inputs', () {
      final owner = computeOwnerValue(
        ownerPassword: 'owner',
        userPassword: 'user',
      );
      List<int> derive() => computeEncryptionKey(
        userPassword: 'user',
        ownerValue: owner,
        permissions: -44,
        documentId: latin1.encode('0123456789abcdef'),
      );
      expect(derive(), derive());
    });

    test('produces a 5-byte key for revision 2', () {
      final owner = computeOwnerValue(ownerPassword: '', userPassword: 'user');
      final key = computeEncryptionKey(
        userPassword: 'user',
        ownerValue: owner,
        permissions: -44,
        documentId: latin1.encode('0123456789abcdef'),
      );
      expect(key, hasLength(5));
    });

    test('a different password yields a different key', () {
      final owner = computeOwnerValue(ownerPassword: '', userPassword: 'a');
      final id = latin1.encode('0123456789abcdef');
      final ka = computeEncryptionKey(
        userPassword: 'a',
        ownerValue: owner,
        permissions: -44,
        documentId: id,
      );
      final kb = computeEncryptionKey(
        userPassword: 'b',
        ownerValue: owner,
        permissions: -44,
        documentId: id,
      );
      expect(ka, isNot(kb));
    });

    test('permissions are part of the key, so tampering breaks decryption', () {
      final owner = computeOwnerValue(ownerPassword: '', userPassword: 'u');
      final id = latin1.encode('0123456789abcdef');
      final allowAll = computeEncryptionKey(
        userPassword: 'u',
        ownerValue: owner,
        permissions: -1,
        documentId: id,
      );
      final restricted = computeEncryptionKey(
        userPassword: 'u',
        ownerValue: owner,
        permissions: -44,
        documentId: id,
      );
      expect(allowAll, isNot(restricted));
    });
  });

  // Getting these backwards silently produces a fixture that does not restrict
  // what it claims to restrict.
  group('permission bit arithmetic (ISO 32000-1 Table 22)', () {
    bool allowsCopy(int p) => (p & 4) != 0;
    bool allowsPrint(int p) => (p & 16) != 0;

    test('-44 allows both printing and copying', () {
      expect(allowsCopy(-44), isTrue);
      expect(allowsPrint(-44), isTrue);
    });

    test('-48 allows printing but denies copying', () {
      expect(allowsCopy(-48), isFalse);
      expect(allowsPrint(-48), isTrue);
    });

    test('-60 does NOT deny copying, despite looking more restrictive', () {
      expect(allowsCopy(-60), isTrue);
      expect(allowsPrint(-60), isFalse);
    });
  });

  group('objectKey', () {
    test('differs per object number', () {
      final fileKey = [1, 2, 3, 4, 5];
      expect(objectKey(fileKey, 1, 0), isNot(objectKey(fileKey, 2, 0)));
    });

    test('is 10 bytes for a 5-byte file key', () {
      expect(objectKey([1, 2, 3, 4, 5], 1, 0), hasLength(10));
    });
  });

  group('encryptObjectBody', () {
    final key = List<int>.generate(10, (i) => i + 1);

    List<int> encrypt(String body) =>
        encryptObjectBody(latin1.encode(body), key);

    test('a body with no strings or streams is unchanged', () {
      const body = '<< /Type /Page /MediaBox [0 0 595 842] >>';
      expect(latin1.decode(encrypt(body)), body);
    });

    // A document whose streams are encrypted but whose strings are not still
    // opens and still renders - and leaks every annotation's text.
    test('a literal string is encrypted', () {
      const body = '<< /Type /Annot /Contents (secret words) >>';
      final out = latin1.decode(encrypt(body));

      expect(out, isNot(contains('secret words')));
      expect(out, startsWith('<< /Type /Annot /Contents ('));
    });

    test('a hexadecimal string is encrypted', () {
      const body = '<< /ID <deadbeef> >>';
      expect(latin1.decode(encrypt(body)), isNot(contains('deadbeef')));
    });

    test('stream data is encrypted', () {
      const payload = 'q 1 0 0 RG Q';
      final body =
          '<< /Length ${payload.length} >>\nstream\n$payload\nendstream';
      expect(latin1.decode(encrypt(body)), isNot(contains(payload)));
    });

    test('the dictionary around a stream survives', () {
      const payload = 'q Q';
      final body =
          '<< /Type /XObject /Length ${payload.length} >>\n'
          'stream\n$payload\nendstream';
      final out = latin1.decode(encrypt(body));

      expect(out, contains('/Type /XObject'));
      expect(out, contains('stream'));
      expect(out, contains('endstream'));
    });

    test('encryption is reversible with the same key', () {
      const payload = 'q 1 0 0 RG Q';
      final body =
          '<< /Length ${payload.length} >>\nstream\n$payload\nendstream';
      final once = encryptObjectBody(latin1.encode(body), key);

      // RC4 is symmetric, so decrypting is the same operation.
      expect(latin1.decode(encryptObjectBody(once, key)), body);
    });
  });

  group('the encryption dictionary', () {
    test('matches the revision 2 shape PDFium already opens', () {
      final d = encryptionDictionary(
        ownerValue: List<int>.filled(32, 0xAB),
        userValue: List<int>.filled(32, 0xCD),
        permissions: -44,
      );

      expect(d, contains('/Filter /Standard'));
      expect(d, contains('/V 1'));
      expect(d, contains('/R 2'));
      expect(d, contains('/P -44'));
      expect(d, contains('/O <'));
      expect(d, contains('/U <'));
    });
  });
}
