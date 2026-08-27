import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_decryption.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

/// Removes password protection, given the password that opens the document.
///
/// A **full rewrite**: every string and stream is decrypted and the /Encrypt
/// dictionary is dropped. An incremental update could not do this — the
/// encrypted bytes would still be there, and a document that merely stops
/// saying it is encrypted is not unlocked, it is broken.
///
/// This is the inverse of what SP-5b writes, and it needs the password. Folio
/// stores no passwords and has no way to open a document without one; that is
/// the whole point of the feature it is undoing.
Uint8List unlockPdf(Uint8List pdf, String password) {
  final text = latin1.decode(pdf, allowInvalid: true);

  final info = readEncryptionInfo(text);
  if (info == null) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'the document is not password protected',
    );
  }
  requireSupportedRevision(info);

  final fileKey = fileKeyFor(info, password);
  if (fileKey == null) {
    throw const WrongPassword();
  }

  final decrypted = <PdfObject>[];

  for (final object in parsePdfObjects(pdf)) {
    // The /Encrypt dictionary describes the lock; with the lock gone it has
    // nothing left to describe.
    if (object.number == info.encryptObjectNumber) continue;

    decrypted.add(
      PdfObject(
        number: object.number,
        generation: object.generation,
        body: _decryptedBody(object, fileKey, info),
      ),
    );
  }

  // writePdfDocument with no encryption drops /Encrypt from the trailer.
  return writePdfDocument(pdf, decrypted);
}

/// The object with its stream and its strings decrypted.
List<int> _decryptedBody(
  PdfObject object,
  List<int> fileKey,
  EncryptionInfo info,
) {
  final body = latin1.decode(object.body, allowInvalid: true);
  final streamAt = body.indexOf('stream');

  final dict = streamAt < 0 ? body : body.substring(0, streamAt);
  final decryptedDict = _withDecryptedStrings(dict, fileKey, info, object);

  if (streamAt < 0) return latin1.encode(decryptedDict);

  final start = body.indexOf('\n', streamAt) + 1;
  final end = body.lastIndexOf('endstream');
  if (start <= 0 || end <= start) return object.body;

  final payload = decryptObjectBody(
    bytes: object.body.sublist(start, end),
    fileKey: fileKey,
    info: info,
    objectNumber: object.number,
    generation: object.generation,
  );

  // /Length described the ciphertext, which is longer than the plaintext for
  // AES. Leaving it would describe a stream that runs past its own end.
  final fixed = decryptedDict.replaceFirst(
    RegExp(r'/Length\s+\d+'),
    '/Length ${payload.length}',
  );

  return [
    ...latin1.encode('${fixed.trimRight()}\nstream\n'),
    ...payload,
    ...latin1.encode('\nendstream'),
  ];
}

/// Decrypts every string in a dictionary.
///
/// Encrypted strings are written as HEX, not as literals: ciphertext is binary
/// and a literal would need escaping. The decryptor has to mirror that, and a
/// version that only looked at `(...)` left every /Title untouched — which
/// reads as mojibake in a viewer's properties panel.
String _withDecryptedStrings(
  String dict,
  List<int> fileKey,
  EncryptionInfo info,
  PdfObject object,
) => dict.replaceAllMapped(RegExp(r'\(([^()]*)\)|<([0-9A-Fa-f]+)>'), (m) {
  // Both forms appear, because the two handlers differ: revision 6 writes
  // every string as hex, revision 2 leaves literals as literals and only
  // hex-encodes what was already hex.
  final literal = m.group(1);
  final hex = m.group(2);
  if (literal == null && (hex == null || hex.length.isOdd)) {
    return m.group(0)!;
  }

  final decrypted = decryptObjectBody(
    bytes: literal != null
        ? latin1.encode(_unescape(literal))
        : [
            for (var i = 0; i + 1 < hex!.length; i += 2)
              int.parse(hex.substring(i, i + 2), radix: 16),
          ],
    fileKey: fileKey,
    info: info,
    objectNumber: object.number,
    generation: object.generation,
  );

  final text = latin1
      .decode(decrypted, allowInvalid: true)
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');

  return '($text)';
});

/// Undoes the escaping a PDF literal string carries.
String _unescape(String s) =>
    s.replaceAll(r'\(', '(').replaceAll(r'\)', ')').replaceAll(r'\\', r'\');
