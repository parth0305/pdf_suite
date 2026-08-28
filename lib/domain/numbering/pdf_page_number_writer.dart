import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfStreamBody;
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/stamp_appearance.dart'
    show helveticaFontObject;
import 'package:folio/domain/numbering/page_numbers.dart';
import 'package:folio/domain/watermark/page_geometry.dart';

/// Stamps a number on every page, by appending an incremental update.
///
/// The original bytes are never rewritten. This is page content rather than an
/// annotation, for the same reason a watermark is: a page number that any
/// viewer can select and delete is not a page number.
Uint8List writePageNumbers(Uint8List pdf, PageNumbering numbering) {
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

  // The page count has to be known before the first number is drawn, because
  // "3 of 12" needs the 12.
  var pageCount = 0;
  while (reader.pageAt(pageCount) != null) {
    pageCount++;
  }
  if (pageCount == 0) {
    throw const EmptyDocument();
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

  void emitStream(int number, String content) {
    final body = pdfStreamBody(content);
    offsets[number] = out.length;
    out
      ..addAll(
        latin1.encode(
          '$number 0 obj\n'
          '<< /Length ${body.bytes.length}${body.filter} >>\nstream\n',
        ),
      )
      ..addAll(body.bytes)
      ..addAll(latin1.encode('\nendstream\nendobj\n'));
  }

  // One font for the whole document, not one per page.
  final fontNum = nextObj++;
  emit(fontNum, helveticaFontObject());

  var numbered = 0;

  for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
    final page = reader.pageAt(pageIndex)!;

    final label = numberTextFor(numbering, pageIndex, pageCount);
    // A skipped page is left completely alone rather than given an empty
    // content stream and a pointless rewrite.
    if (label == null) continue;

    final contentNum = nextObj++;
    emitStream(
      contentNum,
      pageNumberContentStream(
        numbering,
        label,
        mediaBox: mediaBoxOf(index, page),
      ),
    );

    emit(page.objectNumber, _withNumber(page, contentNum, fontNum));
    numbered++;
  }

  if (numbered == 0) {
    throw const EmptyDocument();
  }

  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  for (final n in offsets.keys.toList()..sort()) {
    buffer
      ..writeln('$n 1')
      ..writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');

  final info = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  final infoEntry = info.isEmpty
      ? ''
      : ' /Info ${info.last.group(1)} ${info.last.group(2)} R';

  buffer
    ..writeln(
      '<< /Size $nextObj /Root ${root.group(1)} ${root.group(2)} R'
      '$infoEntry /Prev $prevOffset >>',
    )
    ..writeln('startxref')
    ..writeln('$xrefOffset')
    ..write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}

/// The page with the number APPENDED to /Contents and its font merged into
/// /Resources.
String _withNumber(PdfPageObject page, int contentNum, int fontNum) {
  var body = page.rawDictionary;
  body = body.substring(2, body.length - 2).trim();

  final contents = RegExp(
    r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)',
  ).firstMatch(body);
  final existing = contents == null
      ? ''
      : contents.group(1)!.startsWith('[')
      ? contents.group(1)!.substring(1, contents.group(1)!.length - 1).trim()
      : contents.group(1)!.trim();

  final merged = existing.isEmpty
      ? '/Contents [$contentNum 0 R]'
      : '/Contents [$existing $contentNum 0 R]';

  body = contents == null
      ? '$body $merged'
      : body.replaceRange(contents.start, contents.end, merged);

  return '<< ${_withFont(body, fontNum)} >>';
}

/// Merges the numbering font into whatever /Resources and /Font already exist.
///
/// Inserted after the opening `<<`, which needs no index arithmetic - the same
/// approach the OCR and image-watermark writers settled on after getting the
/// closing brace wrong.
String _withFont(String body, int fontNum) {
  final entry = '/$numberFontName $fontNum 0 R';

  final fonts = RegExp(r'/Font\s*<<').firstMatch(body);
  if (fonts != null) {
    return body.replaceRange(fonts.end, fonts.end, ' $entry');
  }

  final resources = RegExp(r'/Resources\s*<<').firstMatch(body);
  if (resources != null) {
    return body.replaceRange(
      resources.end,
      resources.end,
      ' /Font << $entry >>',
    );
  }

  return '$body /Resources << /Font << $entry >> >>';
}
