// PDF standard security handler, revision 6 (AES-256), per ISO 32000-2.
//
// AES comes from pointycastle: Dart ships no AES, and Bouncy Castle is
// MIT-licensed. SHA-256/384/512 come from package:crypto, already a
// dependency.
//
// NOTE the difference from revision 2: in V5 the file encryption key encrypts
// every string and stream DIRECTLY. There are no per-object keys. Deriving one
// by analogy with R2 produces a document nothing can open.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Everything the /Encrypt dictionary needs for one password.
class AesEncryptionValues {
  const AesEncryptionValues({
    required this.fileKey,
    required this.u,
    required this.ue,
    required this.o,
    required this.oe,
    required this.perms,
  });

  /// 32 bytes. In V5 this encrypts every string and stream directly.
  final List<int> fileKey;

  final List<int> u;
  final List<int> ue;
  final List<int> o;
  final List<int> oe;
  final List<int> perms;
}

/// Algorithm 2.B: the hardened hash revision 6 uses for both passwords.
///
/// Deliberately expensive - it repeats AES and SHA at least 64 times - because
/// its whole purpose is to make guessing a password slow.
List<int> hash2B(List<int> password, List<int> salt, List<int> userData) {
  var k = sha256.convert([...password, ...salt, ...userData]).bytes;

  var round = 0;
  while (true) {
    // K1 is the input repeated 64 times.
    final k1 = <int>[];
    for (var i = 0; i < 64; i++) {
      k1
        ..addAll(password)
        ..addAll(k)
        ..addAll(userData);
    }

    final e = _aesCbcNoPadding(
      key: k.sublist(0, 16),
      iv: k.sublist(16, 32),
      data: k1,
      encrypt: true,
    );

    // The first 16 bytes of E, summed, choose the next digest.
    var sum = 0;
    for (var i = 0; i < 16; i++) {
      sum += e[i];
    }
    k = switch (sum % 3) {
      0 => sha256.convert(e).bytes,
      1 => sha384.convert(e).bytes,
      _ => sha512.convert(e).bytes,
    };

    round++;
    // At least 64 rounds, then stop once the last byte of E is small enough.
    if (round >= 64 && e.last <= round - 32) break;
  }

  return k.sublist(0, 32);
}

/// Builds every value the V5 dictionary needs for [password].
///
/// [randomBytes] is injected so tests are deterministic; production passes a
/// secure generator.
AesEncryptionValues buildAesValues({
  required String password,
  required int permissions,
  required List<int> Function(int count) randomBytes,
  String? ownerPassword,
}) {
  final pw = utf8.encode(password);
  // Without a separate owner password the two are the same, which is what a
  // document with no permissions story wants.
  final ownerPw = utf8.encode(ownerPassword ?? password);
  final fileKey = randomBytes(32);

  // The user entry: a validation salt and a key salt, both 8 bytes.
  final userValidationSalt = randomBytes(8);
  final userKeySalt = randomBytes(8);
  final u = <int>[
    ...hash2B(pw, userValidationSalt, const []),
    ...userValidationSalt,
    ...userKeySalt,
  ];
  final ue = _aesCbcNoPadding(
    key: hash2B(pw, userKeySalt, const []),
    iv: List<int>.filled(16, 0),
    data: fileKey,
    encrypt: true,
  );

  // The owner entry hashes the 48-byte /U as extra data, which is what binds
  // the two passwords to one document.
  final ownerValidationSalt = randomBytes(8);
  final ownerKeySalt = randomBytes(8);
  final o = <int>[
    ...hash2B(ownerPw, ownerValidationSalt, u),
    ...ownerValidationSalt,
    ...ownerKeySalt,
  ];
  final oe = _aesCbcNoPadding(
    key: hash2B(ownerPw, ownerKeySalt, u),
    iv: List<int>.filled(16, 0),
    data: fileKey,
    encrypt: true,
  );

  // /Perms: the permission bits, a marker, and padding, encrypted with the
  // file key in ECB mode so a reader can detect tampering.
  final permsPlain = <int>[
    permissions & 0xFF,
    (permissions >> 8) & 0xFF,
    (permissions >> 16) & 0xFF,
    (permissions >> 24) & 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF,
    0x54, // 'T': metadata is encrypted
    0x61, 0x64, 0x62, // 'adb'
    ...randomBytes(4),
  ];

  return AesEncryptionValues(
    fileKey: fileKey,
    u: u,
    ue: ue,
    o: o,
    oe: oe,
    perms: _aesEcbNoPadding(fileKey, permsPlain),
  );
}

/// AES-256-CBC with [iv] prepended to the ciphertext, PKCS#7 padded.
///
/// Every string and stream gets its OWN iv. Reusing one across a document is
/// a real weakness, not a stylistic choice.
List<int> aesEncrypt(List<int> key, List<int> data, List<int> iv) {
  final padded = <int>[...data];
  final pad = 16 - (data.length % 16);
  padded.addAll(List<int>.filled(pad, pad));

  return <int>[
    ...iv,
    ..._aesCbcNoPadding(key: key, iv: iv, data: padded, encrypt: true),
  ];
}

List<int> _aesCbcNoPadding({
  required List<int> key,
  required List<int> iv,
  required List<int> data,
  required bool encrypt,
}) {
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      encrypt,
      ParametersWithIV(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      ),
    );

  final input = Uint8List.fromList(data);
  final output = Uint8List(input.length);
  for (var offset = 0; offset < input.length; offset += 16) {
    cipher.processBlock(input, offset, output, offset);
  }
  return output;
}

List<int> _aesEcbNoPadding(List<int> key, List<int> data) {
  final cipher = AESEngine()..init(true, KeyParameter(Uint8List.fromList(key)));

  final input = Uint8List.fromList(data);
  final output = Uint8List(input.length);
  for (var offset = 0; offset < input.length; offset += 16) {
    cipher.processBlock(input, offset, output, offset);
  }
  return output;
}
