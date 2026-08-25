import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/annotation.dart';

/// Writes [markups] into [pdf] as real annotation objects, by appending a PDF
/// incremental update.
///
/// The original bytes are never rewritten: new objects, an overridden page
/// dictionary carrying /Annots, a new xref section and a trailer chaining to
/// the previous one are appended. Readers walk that chain backwards.
///
/// Throws [UnsupportedPdfStructure] for documents this technique cannot handle,
/// rather than producing a file whose annotations silently never appear.
Uint8List writeMarkup(Uint8List pdf, List<TextMarkup> markups) {
  if (markups.isEmpty) return pdf;

  final text = latin1.decode(pdf, allowInvalid: true);
  final reader = PdfObjectReader.parse(text);

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

  // Group by page: each page is overridden once, however many markups it has.
  final byPage = <int, List<TextMarkup>>{};
  for (final m in markups) {
    byPage.putIfAbsent(m.pageIndex, () => []).add(m);
  }

  for (final entry in byPage.entries) {
    final page = reader.pageAt(entry.key);
    if (page == null) {
      throw UnsupportedPdfStructure(
        technicalDetail: 'no page object at index ${entry.key}',
      );
    }

    final newRefs = <String>[];
    for (final markup in entry.value) {
      final stream = appearanceStream(markup);
      final apNum = nextObj++;
      emit(
        apNum,
        '${appearanceDict(markup, stream.length)}\n'
        'stream\n${stream}endstream',
      );

      final annotNum = nextObj++;
      final b = markup.boundingRect;
      emit(
        annotNum,
        '<< /Type /Annot /Subtype /${markup.pdfSubtype} '
        '/Rect [${pdfNumber(b.left)} ${pdfNumber(b.bottom)} '
        '${pdfNumber(b.right)} ${pdfNumber(b.top)}] '
        '/QuadPoints [${markup.quadPoints.map(pdfNumber).join(' ')}] '
        '/C [${markup.pdfColour}] /CA 1 /F 4 '
        '/AP << /N $apNum 0 R >> >>',
      );
      newRefs.add('$annotNum 0 R');
    }

    emit(page.objectNumber, reader.withAnnots(page, newRefs));
  }

  // One xref subsection per object: always valid, and avoids having to detect
  // runs of consecutive numbers.
  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  final numbers = offsets.keys.toList()..sort();
  for (final n in numbers) {
    buffer.writeln('$n 1');
    buffer.writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');
  buffer.writeln(
    '<< /Size $nextObj /Root ${root.group(1)} ${root.group(2)} R '
    '/Prev $prevOffset >>',
  );
  buffer.writeln('startxref');
  buffer.writeln('$xrefOffset');
  buffer.write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}
