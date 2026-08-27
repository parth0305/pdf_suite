import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_encryption.dart';
import 'package:folio/domain/pdf/pdf_encryption_aes.dart';
import 'package:pointycastle/export.dart';

/// What a document's /Encrypt dictionary says about how it was locked.
class EncryptionInfo {
  const EncryptionInfo({
    required this.revision,
    required this.o,
    required this.u,
    required this.ue,
    required this.oe,
    required this.permissions,
    required this.documentId,
    required this.encryptObjectNumber,
  });

  final int revision;
  final List<int> o;
  final List<int> u;
  final List<int> ue;
  final List<int> oe;
  final int permissions;
  final List<int> documentId;

  /// So the /Encrypt object itself can be dropped when rewriting.
  final int encryptObjectNumber;

  /// Revision 6 encrypts with the file key directly; revision 2 derives a key
  /// per object. Getting this backwards produces a document nothing can open,
  /// which is the mistake SP-5b was written to avoid.
  bool get usesPerObjectKeys => revision <= 4;
}

/// Reads the /Encrypt dictionary, or null when the document is not encrypted.
EncryptionInfo? readEncryptionInfo(String text) {
  final ref = RegExp(r'/Encrypt\s+(\d+)\s+\d+\s+R').allMatches(text);
  if (ref.isEmpty) return null;

  final number = int.parse(ref.last.group(1)!);
  final object = RegExp(
    '(?<![0-9])$number\\s+[0-9]+\\s+obj(.*?)endobj',
    dotAll: true,
  ).firstMatch(text);
  if (object == null) return null;

  final dict = object.group(1)!;
  final revision = int.tryParse(
    RegExp(r'/R\s+(\d+)').firstMatch(dict)?.group(1) ?? '',
  );
  if (revision == null) return null;

  final ids = RegExp(r'/ID\s*\[\s*<([0-9A-Fa-f]*)>').firstMatch(text);

  return EncryptionInfo(
    revision: revision,
    o: _hexOrLiteral(dict, 'O'),
    u: _hexOrLiteral(dict, 'U'),
    ue: _hexOrLiteral(dict, 'UE'),
    oe: _hexOrLiteral(dict, 'OE'),
    permissions:
        int.tryParse(
          RegExp(r'/P\s+(-?\d+)').firstMatch(dict)?.group(1) ?? '',
        ) ??
        -4,
    documentId: _fromHex(ids?.group(1) ?? ''),
    encryptObjectNumber: number,
  );
}

/// Recovers the file key from [password], or null when it does not open the
/// document.
///
/// Both the user and the owner password are tried: either opens the file, and
/// a person removing protection from their own document may well know only one
/// of them.
List<int>? fileKeyFor(EncryptionInfo info, String password) {
  if (info.usesPerObjectKeys) {
    final key = computeEncryptionKey(
      userPassword: password,
      ownerValue: info.o,
      permissions: info.permissions,
      documentId: info.documentId,
    );

    // Revision 2's check: recomputing /U from the key must reproduce it.
    final expected = computeUserValue(key);
    return _same(expected, info.u.take(expected.length).toList()) ? key : null;
  }

  final pw = utf8.encode(password);

  // Algorithm 2.A, user branch.
  if (info.u.length >= 48) {
    final validation = info.u.sublist(32, 40);
    final keySalt = info.u.sublist(40, 48);
    if (_same(hash2B(pw, validation, const []), info.u.sublist(0, 32))) {
      return aesCbcDecrypt(hash2B(pw, keySalt, const []), info.ue);
    }
  }

  // Owner branch: the 48-byte /U is mixed in as extra data.
  if (info.o.length >= 48 && info.u.length >= 48) {
    final validation = info.o.sublist(32, 40);
    final keySalt = info.o.sublist(40, 48);
    if (_same(hash2B(pw, validation, info.u), info.o.sublist(0, 32))) {
      return aesCbcDecrypt(hash2B(pw, keySalt, info.u), info.oe);
    }
  }

  return null;
}

/// Decrypts one string or stream body.
///
/// RC4 is its own inverse, so revision 2 needs no separate routine. AES
/// prefixes its initialisation vector to the ciphertext and pads to the block
/// size, both of which have to be undone here.
List<int> decryptObjectBody({
  required List<int> bytes,
  required List<int> fileKey,
  required EncryptionInfo info,
  required int objectNumber,
  required int generation,
}) {
  if (info.usesPerObjectKeys) {
    return rc4(objectKey(fileKey, objectNumber, generation), bytes);
  }

  if (bytes.length < 16) return bytes;

  final iv = bytes.sublist(0, 16);
  final body = bytes.sublist(16);
  if (body.isEmpty || body.length % 16 != 0) return bytes;

  final plain = aesCbcDecrypt(fileKey, body, iv: iv);

  // Strip PKCS#7 padding. A malformed pad is left alone rather than trusted:
  // trimming by a wrong count would silently truncate the content.
  final pad = plain.isEmpty ? 0 : plain.last;
  if (pad < 1 || pad > 16 || pad > plain.length) return plain;

  return plain.sublist(0, plain.length - pad);
}

/// AES-256-CBC decryption, no padding removal.
List<int> aesCbcDecrypt(List<int> key, List<int> data, {List<int>? iv}) {
  if (data.isEmpty || data.length % 16 != 0) return const [];

  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      false,
      ParametersWithIV(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv ?? List<int>.filled(16, 0)),
      ),
    );

  final input = Uint8List.fromList(data);
  final output = Uint8List(input.length);
  for (var o = 0; o < input.length; o += 16) {
    cipher.processBlock(input, o, output, o);
  }
  return output;
}

/// Refuses a document whose encryption Folio cannot undo.
void requireSupportedRevision(EncryptionInfo info) {
  if (info.revision == 2 || info.revision == 3 || info.revision == 6) return;

  throw UnsupportedPdfStructure(
    technicalDetail: 'unsupported security handler revision ${info.revision}',
  );
}

List<int> _hexOrLiteral(String dict, String key) {
  final hex = RegExp('/$key\\s*<([0-9A-Fa-f]*)>').firstMatch(dict);
  if (hex != null) return _fromHex(hex.group(1)!);

  final literal = RegExp('/$key\\s*\\((.*?)\\)', dotAll: true).firstMatch(dict);
  return literal == null ? const [] : latin1.encode(literal.group(1)!);
}

List<int> _fromHex(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
