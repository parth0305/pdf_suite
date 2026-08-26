// PDF standard security handler, revision 2 (RC4, 40-bit), per ISO 32000-1
// section 7.6.3.
//
// Written by hand because no permissively licensed Dart package produces an
// encrypted PDF. It began life generating test fixtures; SP-5a moved it into
// the app, where the object layer uses it to encrypt documents.
//
// RC4-40 is NOT protection worth offering to a user. Nothing in the app
// exposes it: it exists to prove the encryption pipeline against a cipher that
// is already verified, so that when AES-256 arrives the only new variable is
// the cipher.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The 32-byte padding string from ISO 32000-1, Table 3.15.
const List<int> kPadding = [
  0x28,
  0xBF,
  0x4E,
  0x5E,
  0x4E,
  0x75,
  0x8A,
  0x41,
  0x64,
  0x00,
  0x4E,
  0x56,
  0xFF,
  0xFA,
  0x01,
  0x08,
  0x2E,
  0x2E,
  0x00,
  0xB6,
  0xD0,
  0x68,
  0x3E,
  0x80,
  0x2F,
  0x0C,
  0xA9,
  0xFE,
  0x64,
  0x53,
  0x69,
  0x7A,
];

/// RC4 stream cipher. Key-scheduling followed by pseudo-random generation.
Uint8List rc4(List<int> key, List<int> data) {
  final s = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xFF;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
  }

  final out = Uint8List(data.length);
  var i = 0;
  j = 0;
  for (var k = 0; k < data.length; k++) {
    i = (i + 1) & 0xFF;
    j = (j + s[i]) & 0xFF;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
    out[k] = data[k] ^ s[(s[i] + s[j]) & 0xFF];
  }
  return out;
}

/// Pads or truncates a password to exactly 32 bytes (Algorithm 2, step a).
List<int> padPassword(String password) {
  final bytes = latin1.encode(password);
  if (bytes.length >= 32) return bytes.sublist(0, 32);
  return [...bytes, ...kPadding.take(32 - bytes.length)];
}

/// Algorithm 3: compute the /O entry.
List<int> computeOwnerValue({
  required String ownerPassword,
  required String userPassword,
}) {
  final padded = padPassword(
    ownerPassword.isEmpty ? userPassword : ownerPassword,
  );
  final digest = md5.convert(padded).bytes;
  // Revision 2 uses a 5-byte RC4 key and a single pass.
  return rc4(digest.sublist(0, 5), padPassword(userPassword));
}

/// Algorithm 2: compute the file encryption key.
List<int> computeEncryptionKey({
  required String userPassword,
  required List<int> ownerValue,
  required int permissions,
  required List<int> documentId,
}) {
  final input = <int>[
    ...padPassword(userPassword),
    ...ownerValue,
    // /P as a 4-byte little-endian signed integer.
    permissions & 0xFF,
    (permissions >> 8) & 0xFF,
    (permissions >> 16) & 0xFF,
    (permissions >> 24) & 0xFF,
    ...documentId,
  ];
  return md5.convert(input).bytes.sublist(0, 5);
}

/// Algorithm 4 (revision 2): compute the /U entry.
List<int> computeUserValue(List<int> encryptionKey) =>
    rc4(encryptionKey, kPadding);

/// Per-object key: MD5(fileKey + objNum[3 LE] + genNum[2 LE]), truncated.
List<int> objectKey(List<int> fileKey, int objNum, int genNum) {
  final input = <int>[
    ...fileKey,
    objNum & 0xFF,
    (objNum >> 8) & 0xFF,
    (objNum >> 16) & 0xFF,
    genNum & 0xFF,
    (genNum >> 8) & 0xFF,
  ];
  final digest = md5.convert(input).bytes;
  final length = fileKey.length + 5;
  return digest.sublist(0, length > 16 ? 16 : length);
}

/// Renders bytes as a PDF hexadecimal string literal.
String hexString(List<int> bytes) =>
    '<${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>';
