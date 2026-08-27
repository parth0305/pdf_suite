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

/// Encrypts every literal string, hexadecimal string and stream inside a
/// single object's body, using that object's key.
///
/// RC4 is symmetric, so applying this twice with the same key returns the
/// original.
///
/// The caller must NOT pass the /Encrypt dictionary or the document /ID: a
/// reader needs both in the clear before it can derive any key.
List<int> encryptObjectBody(List<int> body, List<int> objectKey) {
  final text = latin1.decode(body, allowInvalid: true);

  // A stream is handled whole, because its data is binary and must not be
  // scanned for string delimiters.
  final streamAt = text.indexOf('stream');
  if (streamAt >= 0) {
    var dataStart = streamAt + 'stream'.length;
    if (text.startsWith('\r\n', dataStart)) {
      dataStart += 2;
    } else if (text.startsWith('\n', dataStart)) {
      dataStart += 1;
    }
    final dataEnd = text.lastIndexOf('endstream');
    if (dataEnd > dataStart) {
      return <int>[
        ...latin1.encode(
          _encryptStrings(text.substring(0, streamAt), objectKey),
        ),
        ...latin1.encode(text.substring(streamAt, dataStart)),
        ...rc4(objectKey, body.sublist(dataStart, dataEnd)),
        ...latin1.encode(text.substring(dataEnd)),
      ];
    }
  }

  return latin1.encode(_encryptStrings(text, objectKey));
}

/// Encrypts the literal and hexadecimal strings in a dictionary fragment.
String _encryptStrings(String text, List<int> key) {
  var out = text.replaceAllMapped(RegExp(r'\(([^()]*)\)'), (m) {
    final encrypted = rc4(key, latin1.encode(m.group(1)!));
    return '(${_escape(latin1.decode(encrypted))})';
  });

  // hexString already wraps its output in angle brackets, so return it as-is.
  out = out.replaceAllMapped(
    RegExp(r'<([0-9A-Fa-f]+)>'),
    (m) => hexString(rc4(key, _fromHex(m.group(1)!))),
  );

  return out;
}

/// Escapes the characters that would end a PDF literal string early.
String _escape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');

List<int> _fromHex(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

/// Encrypts every string and stream in an object body with AES, using the file
/// key directly.
///
/// V5 has no per-object keys - that is revision 2's scheme, and applying it
/// here produces a document nothing can open. Each value gets its own random
/// initialisation vector.
List<int> encryptObjectBodyAes(
  List<int> body,
  List<int> fileKey,
  List<int> Function(int count) randomBytes,
  List<int> Function(List<int> key, List<int> data, List<int> iv) encrypt,
) {
  final text = latin1.decode(body, allowInvalid: true);

  final streamAt = text.indexOf('stream');
  if (streamAt >= 0) {
    var dataStart = streamAt + 'stream'.length;
    if (text.startsWith('\r\n', dataStart)) {
      dataStart += 2;
    } else if (text.startsWith('\n', dataStart)) {
      dataStart += 1;
    }
    final dataEnd = text.lastIndexOf('endstream');
    if (dataEnd > dataStart) {
      final cipher = encrypt(
        fileKey,
        body.sublist(dataStart, dataEnd),
        randomBytes(16),
      );
      // /Length must describe the ciphertext, IV included.
      final head = _aesStrings(
        text.substring(0, streamAt),
        fileKey,
        randomBytes,
        encrypt,
      ).replaceAll(RegExp(r'/Length\s+\d+'), '/Length ${cipher.length}');

      return <int>[
        ...latin1.encode(head),
        ...latin1.encode(text.substring(streamAt, dataStart)),
        ...cipher,
        ...latin1.encode(text.substring(dataEnd)),
      ];
    }
  }

  return latin1.encode(_aesStrings(text, fileKey, randomBytes, encrypt));
}

String _aesStrings(
  String text,
  List<int> fileKey,
  List<int> Function(int) randomBytes,
  List<int> Function(List<int>, List<int>, List<int>) encrypt,
) {
  // ONE pass over both forms. Two passes - literals first, then hex - encrypt
  // every literal TWICE, because the first pass turns a literal into hex and
  // the second pass then finds it. A reader decrypting once got ciphertext
  // where a /Title should be, and nothing noticed until the decryptor was
  // written and could not read Folio's own output back.
  return text.replaceAllMapped(RegExp(r'\(([^()]*)\)|<([0-9A-Fa-f]+)>'), (m) {
    final plain = m.group(1) != null
        ? latin1.encode(m.group(1)!)
        : _fromHex(m.group(2)!);

    // Hexadecimal, because ciphertext is binary and would need escaping.
    return hexString(encrypt(fileKey, plain, randomBytes(16)));
  });
}
