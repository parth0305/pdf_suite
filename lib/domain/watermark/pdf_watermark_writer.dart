import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfStreamBody;
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/stamp_appearance.dart'
    show helveticaFontObject;
import 'package:folio/domain/watermark/page_geometry.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'package:folio/domain/watermark/watermark_content.dart';

/// Stamps [mark] across every page by appending a PDF incremental update.
///
/// The original bytes are never rewritten: a content stream per page, one
/// shared font and graphics state, and an overridden page dictionary each.
Uint8List writeWatermark(Uint8List pdf, Watermark mark) {
  if (mark.text.trim().isEmpty) {
    throw ArgumentError.value(mark.text, 'text', 'a watermark needs text');
  }

  final text = latin1.decode(pdf, allowInvalid: true);
  final reader = PdfObjectReader.parse(text);
  final index = PdfObjectIndex.parse(text);

  if (reader.usesXrefStream) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'PDF 1.5+ cross-reference stream',
    );
  }

  final startxref = RegExp(
    r'startxref\s+(\d+)\s*%%EOF\s*$',
  ).firstMatch(text.trimRight());
  final roots = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  final sizes = RegExp(r'/Size\s+(\d+)').allMatches(text);

  if (startxref == null || roots.isEmpty || sizes.isEmpty) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'no classic trailer with /Root, /Size and startxref',
    );
  }

  final prevOffset = int.parse(startxref.group(1)!);
  final root = roots.last;
  var nextObj = int.parse(sizes.last.group(1)!);

  final out = <int>[...pdf];
  if (out.isNotEmpty && out.last != 0x0a) out.add(0x0a);

  final offsets = <int, int>{};
  void emit(int number, String body) {
    offsets[number] = out.length;
    out.addAll(latin1.encode('$number 0 obj\n$body\nendobj\n'));
  }

  /// Emits a content stream, deflated when that makes it smaller.
  ///
  /// The bytes are appended directly rather than spliced into a string:
  /// deflate output is binary and would not survive latin1 round-tripping.
  /// /Length and /Filter both describe the bytes actually written, never the
  /// text they came from.
  void emitStream(int number, String content) {
    final body = pdfStreamBody(content);
    offsets[number] = out.length;
    out
      ..addAll(
        latin1.encode(
          '$number 0 obj\n'
          '<< /Length ${body.bytes.length}${body.filter} >>\n'
          'stream\n',
        ),
      )
      ..addAll(body.bytes)
      ..addAll(latin1.encode('\nendstream\nendobj\n'));
  }

  // One font and one graphics state for the whole document, not one per page.
  final fontNum = nextObj++;
  emit(fontNum, helveticaFontObject());
  final gsNum = nextObj++;
  emit(gsNum, watermarkExtGState(mark));

  for (var pageIndex = 0; ; pageIndex++) {
    final page = reader.pageAt(pageIndex);
    if (page == null) break;

    // Per page: a page may be a different size from its neighbours, and a
    // watermark centred on the wrong one lands off the paper.
    final stream = watermarkContentStream(
      mark,
      mediaBox: mediaBoxOf(index, page),
    );

    final contentNum = nextObj++;
    emitStream(contentNum, stream);

    emit(
      page.objectNumber,
      reader.withContentsAndResources(
        page,
        contentObjectNumber: contentNum,
        fontObjectNumber: fontNum,
        extGStateObjectNumber: gsNum,
      ),
    );
  }

  // One xref subsection per object: always valid, and avoids having to detect
  // runs of consecutive numbers.
  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  for (final n in offsets.keys.toList()..sort()) {
    buffer.writeln('$n 1');
    buffer.writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');

  // Carry /Info forward: the newest trailer wins, and one without it discards
  // the document's title and author.
  final info = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  final infoEntry = info.isEmpty
      ? ''
      : ' /Info ${info.last.group(1)} ${info.last.group(2)} R';

  buffer.writeln(
    '<< /Size $nextObj /Root ${root.group(1)} ${root.group(2)} R'
    '$infoEntry /Prev $prevOffset >>',
  );
  buffer.writeln('startxref');
  buffer.writeln('$xrefOffset');
  buffer.write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}
