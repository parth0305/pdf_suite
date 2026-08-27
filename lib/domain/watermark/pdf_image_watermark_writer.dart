import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfStreamBody;
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/watermark/image_watermark_content.dart';
import 'package:folio/domain/watermark/page_geometry.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// The resource name Folio gives an image watermark.
///
/// Distinctive so removal can find it with certainty, exactly as `/WMF1` does
/// for the text mark.
const imageWatermarkName = 'WMIm';

/// Stamps [mark] across every page by appending an incremental update.
///
/// The original bytes are never rewritten: one image, one mask, and a content
/// stream per page.
Uint8List writeImageWatermark(Uint8List pdf, ImageWatermark mark) {
  if (!mark.isUsable) {
    throw ArgumentError.value(mark, 'mark', 'the image is empty or mis-sized');
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

  void emitBinary(int number, String dict, List<int> bytes) {
    offsets[number] = out.length;
    out
      ..addAll(latin1.encode('$number 0 obj\n$dict\nstream\n'))
      ..addAll(bytes)
      ..addAll(latin1.encode('\nendstream\nendobj\n'));
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

  // One image and one mask for the whole document, however many pages use it.
  final samples = imageWatermarkSamples(mark);

  final maskNum = nextObj++;
  emitBinary(
    maskNum,
    '<< /Type /XObject /Subtype /Image '
    '/Width ${mark.pixelWidth} /Height ${mark.pixelHeight} '
    '/ColorSpace /DeviceGray /BitsPerComponent 8 '
    '/Length ${samples.alpha.length} /Filter /FlateDecode >>',
    samples.alpha,
  );

  final imageNum = nextObj++;
  emitBinary(
    imageNum,
    '<< /Type /XObject /Subtype /Image '
    '/Width ${mark.pixelWidth} /Height ${mark.pixelHeight} '
    '/ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask $maskNum 0 R '
    '/Length ${samples.rgb.length} /Filter /FlateDecode >>',
    samples.rgb,
  );

  for (var pageIndex = 0; ; pageIndex++) {
    final page = reader.pageAt(pageIndex);
    if (page == null) break;

    // Per page: a page may be a different size from its neighbours, and a mark
    // centred on the wrong one lands off the paper.
    final contentNum = nextObj++;
    emitStream(
      contentNum,
      imageWatermarkContentStream(mark, mediaBox: mediaBoxOf(index, page)),
    );

    emit(page.objectNumber, _withImage(page, contentNum, imageNum));
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

/// The page with the mark's content APPENDED and its image merged into
/// /Resources.
///
/// Appended and merged, never replaced: the page's own drawing and its own
/// images have to survive.
String _withImage(PdfPageObject page, int contentNum, int imageNum) {
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

  return '<< ${_withXObject(body, imageNum)} >>';
}

/// Merges `/WMIm` into whatever /Resources and /XObject already exist.
///
/// The entry is inserted immediately after the opening `<<` rather than before
/// the matching `>>`. Both are correct PDF, and only one of them needs the
/// closing brace's index - which is the arithmetic that is easy to get wrong,
/// and did go wrong here first time round.
String _withXObject(String body, int imageNum) {
  final entry = '/$imageWatermarkName $imageNum 0 R';

  final xobjects = RegExp(r'/XObject\s*<<').firstMatch(body);
  if (xobjects != null) {
    return body.replaceRange(xobjects.end, xobjects.end, ' $entry');
  }

  final resources = RegExp(r'/Resources\s*<<').firstMatch(body);
  if (resources != null) {
    return body.replaceRange(
      resources.end,
      resources.end,
      ' /XObject << $entry >>',
    );
  }

  return '$body /Resources << /XObject << $entry >> >>';
}
