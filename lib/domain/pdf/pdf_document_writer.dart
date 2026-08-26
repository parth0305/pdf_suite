import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_encryption.dart';
import 'package:folio/domain/pdf/pdf_encryption_dictionary.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

/// How to encrypt a document on the way out.
class PdfEncryption {
  const PdfEncryption({required this.userPassword, this.permissions = -44});

  final String userPassword;

  /// The /P bit field. -44 is the value the existing fixtures use.
  final int permissions;
}

/// Rebuilds a complete PDF: header, every object, a fresh cross-reference
/// table, a trailer.
///
/// This is a REWRITE, not an incremental update - there is no `/Prev`, because
/// the previous cross-reference table does not exist in the new file. That is
/// what encryption needs: every string and stream has to be re-emitted, and
/// nothing can be appended to achieve it.
Uint8List writePdfDocument(
  List<int> original,
  List<PdfObject> objects, {
  PdfEncryption? encryption,
}) {
  if (objects.isEmpty) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'no indirect objects found',
    );
  }

  final text = latin1.decode(original, allowInvalid: true);
  final roots = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  if (roots.isEmpty) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'no /Root in any trailer',
    );
  }
  final root = roots.last;
  final infos = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text);

  // The binary comment marks the file as containing 8-bit data, so tools do
  // not mangle it as text.
  final highest = objects.map((o) => o.number).reduce((a, b) => a > b ? a : b);

  // Revision 2 derives its key from the first /ID element, so one must exist
  // and must NOT itself be encrypted. Deterministic, because a random ID would
  // make the writer untestable.
  final documentId = List<int>.generate(16, (i) => (i * 7 + 13) & 0xFF);
  final encryptNumber = highest + 1;

  List<int>? fileKey;
  List<int>? ownerValue;
  if (encryption != null) {
    ownerValue = computeOwnerValue(
      ownerPassword: encryption.userPassword,
      userPassword: encryption.userPassword,
    );
    fileKey = computeEncryptionKey(
      userPassword: encryption.userPassword,
      ownerValue: ownerValue,
      permissions: encryption.permissions,
      documentId: documentId,
    );
  }

  final out = <int>[...latin1.encode('%PDF-1.4\n%âãÏÓ\n')];
  final offsets = <int, int>{};

  for (final o in objects) {
    offsets[o.number] = out.length;
    // Each object gets its OWN key. Reusing the file key produces a document
    // that opens in some readers and not others.
    final body = fileKey == null
        ? o.body
        : encryptObjectBody(o.body, objectKey(fileKey, o.number, o.generation));
    out
      ..addAll(latin1.encode('${o.number} ${o.generation} obj'))
      ..addAll(body)
      ..addAll(latin1.encode('endobj\n'));
  }

  // The /Encrypt dictionary is never itself encrypted: a reader needs it
  // before it can derive any key.
  if (encryption != null) {
    offsets[encryptNumber] = out.length;
    out.addAll(
      latin1.encode(
        '$encryptNumber 0 obj\n'
        '${encryptionDictionary(ownerValue: ownerValue!, userValue: computeUserValue(fileKey!), permissions: encryption.permissions)}\n'
        'endobj\n',
      ),
    );
  }

  final lastNumber = encryption == null ? highest : encryptNumber;
  final xrefOffset = out.length;

  final buffer = StringBuffer('xref\n0 ${lastNumber + 1}\n')
    ..writeln('0000000000 65535 f ');
  for (var n = 1; n <= lastNumber; n++) {
    final at = offsets[n];
    // A number nobody used is a free entry, not an error.
    buffer.writeln(
      at == null
          ? '0000000000 65535 f '
          : '${at.toString().padLeft(10, '0')} 00000 n ',
    );
  }

  buffer
    ..writeln('trailer')
    ..writeln(
      '<< /Size ${lastNumber + 1} /Root ${root.group(1)} ${root.group(2)} R'
      '${infos.isEmpty ? '' : ' /Info ${infos.last.group(1)} '
                '${infos.last.group(2)} R'}'
      '${encryption == null ? '' : ' /Encrypt $encryptNumber 0 R'}'
      ' /ID [${hexString(documentId)} ${hexString(documentId)}] >>',
    )
    ..writeln('startxref')
    ..writeln('$xrefOffset')
    ..write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}
