import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

/// Rebuilds a complete PDF: header, every object, a fresh cross-reference
/// table, a trailer.
///
/// This is a REWRITE, not an incremental update - there is no `/Prev`, because
/// the previous cross-reference table does not exist in the new file. That is
/// what encryption needs: every string and stream has to be re-emitted, and
/// nothing can be appended to achieve it.
Uint8List writePdfDocument(List<int> original, List<PdfObject> objects) {
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
  final out = <int>[...latin1.encode('%PDF-1.4\n%âãÏÓ\n')];
  final offsets = <int, int>{};

  for (final o in objects) {
    offsets[o.number] = out.length;
    out
      ..addAll(latin1.encode('${o.number} ${o.generation} obj'))
      ..addAll(o.body)
      ..addAll(latin1.encode('endobj\n'));
  }

  final highest = objects.map((o) => o.number).reduce((a, b) => a > b ? a : b);
  final xrefOffset = out.length;

  final buffer = StringBuffer('xref\n0 ${highest + 1}\n')
    ..writeln('0000000000 65535 f ');
  for (var n = 1; n <= highest; n++) {
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
      '<< /Size ${highest + 1} /Root ${root.group(1)} ${root.group(2)} R'
      '${infos.isEmpty ? '' : ' /Info ${infos.last.group(1)} '
                '${infos.last.group(2)} R'} >>',
    )
    ..writeln('startxref')
    ..writeln('$xrefOffset')
    ..write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}
