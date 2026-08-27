import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfStreamBody;
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/stamp_appearance.dart'
    show helveticaFontObject;

/// Adds an invisible text layer to pages, by appending an incremental update.
///
/// An incremental update is right here, unlike redaction: nothing is being
/// removed, so leaving the original bytes at the front of the file is exactly
/// what should happen. The original document is never rewritten.
///
/// [layers] maps a page index to its content-stream fragment. A page with no
/// entry, or an empty one, is left completely untouched.
Uint8List writeOcrLayer(Uint8List pdf, Map<int, String> layers) {
  final wanted = {
    for (final e in layers.entries)
      if (e.value.trim().isNotEmpty) e.key: e.value,
  };
  if (wanted.isEmpty) {
    throw ArgumentError.value(layers, 'layers', 'no text to add');
  }

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

  /// Deflate output is binary and would not survive latin1 round-tripping, so
  /// the bytes are appended rather than spliced into a string.
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

  for (final entry in wanted.entries) {
    final page = reader.pageAt(entry.key);
    if (page == null) {
      throw ArgumentError.value(entry.key, 'layers', 'no such page');
    }

    final contentNum = nextObj++;
    emitStream(contentNum, entry.value);
    emit(page.objectNumber, _withOcrLayer(page, contentNum, fontNum));
  }

  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  for (final n in offsets.keys.toList()..sort()) {
    buffer
      ..writeln('$n 1')
      ..writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');

  // Carry /Info forward: the newest trailer wins, and one without it discards
  // the document's title and author.
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

/// The page dictionary with the OCR stream APPENDED to /Contents and the font
/// merged into /Resources.
///
/// Appended, never substituted: the page's own drawing - the scan itself - has
/// to keep happening, and the text layer draws nothing anyway.
String _withOcrLayer(PdfPageObject page, int contentNum, int fontNum) {
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

/// Merges `/OcF1` into whatever `/Resources` and `/Font` already exist.
///
/// Replacing them would strip the page's own fonts and images, which for a
/// scanned page means losing the scan.
String _withFont(String body, int fontNum) {
  const entry = '/OcF1';
  final font = '$entry $fontNum 0 R';

  final resources = RegExp(r'/Resources\s*<<').firstMatch(body);
  if (resources == null) {
    return '$body /Resources << /Font << $font >> >>';
  }

  final close = PdfObjectIndex.matchingClose(body, resources.end - 2);
  final inner = body.substring(resources.end, close - 2);

  final fonts = RegExp(r'/Font\s*<<').firstMatch(inner);
  if (fonts == null) {
    return '${body.substring(0, resources.end)} /Font << $font >>'
        '${body.substring(resources.end, close)}'
        '${body.substring(close)}';
  }

  final fontClose = PdfObjectIndex.matchingClose(inner, fonts.end - 2);
  final withFont =
      '${inner.substring(0, fonts.end)} $font${inner.substring(fonts.end, fontClose - 2)}'
      '${inner.substring(fontClose - 2)}';

  return body.substring(0, resources.end) +
      withFont +
      body.substring(close - 2);
}
