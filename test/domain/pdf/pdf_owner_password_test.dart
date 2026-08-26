// Verifies the owner password and permission bits the way a READER does:
// this file implements ISO 32000-2 Algorithm 2.A independently instead of
// asserting that the writer wrote what the writer wrote.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/pdf/pdf_encryption_aes.dart';
import 'package:folio/domain/pdf/pdf_permissions.dart';
import 'package:pointycastle/export.dart';

/// AES-256-CBC decryption with a zero IV and no padding, which is how a
/// reader unwraps /UE and /OE.
List<int> _decryptCbc(List<int> key, List<int> data) {
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      false,
      ParametersWithIV(KeyParameter(Uint8List.fromList(key)), Uint8List(16)),
    );

  final input = Uint8List.fromList(data);
  final output = Uint8List(input.length);
  for (var o = 0; o < input.length; o += 16) {
    cipher.processBlock(input, o, output, o);
  }
  return output;
}

List<int> _decryptEcb(List<int> key, List<int> data) {
  final cipher = AESEngine()
    ..init(false, KeyParameter(Uint8List.fromList(key)));

  final input = Uint8List.fromList(data);
  final output = Uint8List(input.length);
  for (var o = 0; o < input.length; o += 16) {
    cipher.processBlock(input, o, output, o);
  }
  return output;
}

/// Algorithm 2.A, user branch. Null means the password did not validate.
List<int>? _openAsUser(AesEncryptionValues v, String password) {
  final pw = utf8.encode(password);
  final validationSalt = v.u.sublist(32, 40);
  final keySalt = v.u.sublist(40, 48);

  if (!_same(hash2B(pw, validationSalt, const []), v.u.sublist(0, 32))) {
    return null;
  }
  return _decryptCbc(hash2B(pw, keySalt, const []), v.ue);
}

/// Algorithm 2.A, owner branch. The 48-byte /U is mixed in as extra data.
List<int>? _openAsOwner(AesEncryptionValues v, String password) {
  final pw = utf8.encode(password);
  final validationSalt = v.o.sublist(32, 40);
  final keySalt = v.o.sublist(40, 48);

  if (!_same(hash2B(pw, validationSalt, v.u), v.o.sublist(0, 32))) return null;
  return _decryptCbc(hash2B(pw, keySalt, v.u), v.oe);
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Deterministic bytes: encryption values must be reproducible in a test.
List<int> _counted(int count) =>
    List<int>.generate(count, (i) => (i * 7) & 0xFF);

void main() {
  group('owner password', () {
    test('a distinct owner password recovers the same file key', () {
      final v = buildAesValues(
        password: 'reader',
        ownerPassword: 'author',
        permissions: PdfPermissions.all.bits,
        randomBytes: _counted,
      );

      expect(_openAsUser(v, 'reader'), v.fileKey);
      expect(
        _openAsOwner(v, 'author'),
        v.fileKey,
        reason: 'both passwords must unlock the same document',
      );
    });

    // The mutation this catches: hashing the user password into /O, which is
    // what the code did before this slice.
    test('the user password does not validate as the owner', () {
      final v = buildAesValues(
        password: 'reader',
        ownerPassword: 'author',
        permissions: PdfPermissions.all.bits,
        randomBytes: _counted,
      );

      expect(_openAsOwner(v, 'reader'), isNull);
      expect(_openAsUser(v, 'author'), isNull);
    });

    test('a wrong password validates as neither', () {
      final v = buildAesValues(
        password: 'reader',
        ownerPassword: 'author',
        permissions: PdfPermissions.all.bits,
        randomBytes: _counted,
      );

      expect(_openAsUser(v, 'wrong'), isNull);
      expect(_openAsOwner(v, 'wrong'), isNull);
    });

    test(
      'omitting the owner password lets the user password serve as both',
      () {
        final v = buildAesValues(
          password: 'only',
          permissions: PdfPermissions.all.bits,
          randomBytes: _counted,
        );

        expect(_openAsUser(v, 'only'), v.fileKey);
        expect(_openAsOwner(v, 'only'), v.fileKey);
      },
    );
  });

  group('/Perms', () {
    // /Perms is the tamper check: a reader decrypts it and compares against
    // the /P it read in the clear. If the writer sends a different value the
    // document's permissions are not trustworthy.
    test('carries the permission bits the caller asked for', () {
      final permissions = const PdfPermissions(
        printing: false,
        copying: false,
      ).bits;
      final v = buildAesValues(
        password: 'pw',
        permissions: permissions,
        randomBytes: _counted,
      );

      final plain = _decryptEcb(v.fileKey, v.perms);
      final recovered =
          plain[0] | (plain[1] << 8) | (plain[2] << 16) | (plain[3] << 24);

      expect(recovered.toSigned(32), permissions);
      expect(
        String.fromCharCodes(plain.sublist(9, 12)),
        'adb',
        reason: 'the marker a reader uses to know it decrypted correctly',
      );
    });

    test('a different permission set produces different bits', () {
      List<int> permsFor(PdfPermissions p) => buildAesValues(
        password: 'pw',
        permissions: p.bits,
        randomBytes: _counted,
      ).perms;

      expect(
        permsFor(const PdfPermissions(printing: false)),
        isNot(permsFor(PdfPermissions.all)),
      );
    });
  });
}
