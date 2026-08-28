import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/editing/font_encoding.dart';

/// A font as a page refers to it: how to read its bytes, and how wide its
/// glyphs are.
class PageFont {
  const PageFont({required this.decoder, required this.widths, this.byCode});

  /// Null when the document gives no way to read this font's bytes - in which
  /// case its text is shown but cannot be edited.
  final FontDecoder? decoder;

  /// Width by character code, in thousandths of the text size.
  final Map<int, double> widths;

  /// The default for codes the widths do not list.
  final double? byCode;

  double? widthOf(int code) => widths[code] ?? byCode;
}

/// Reads the fonts a page's resources name.
///
/// `/Resources` is inheritable, so a page that declares none uses its
/// parent's - and a reader that looks only at the page finds no fonts at all
/// on documents that put them on the pages node.
Map<String, PageFont> pageFonts(
  Uint8List pdf,
  PdfObjectIndex index,
  String pageDictionary,
) {
  final resources = _inherited(index, pageDictionary, 'Resources');
  if (resources == null) return const {};

  final fonts = _dictionaryFor(index, resources, 'Font');
  if (fonts == null) return const {};

  final out = <String, PageFont>{};

  for (final match in RegExp(
    r'/([^\s/<>\[\]]+)\s+(\d+)\s+\d+\s+R',
  ).allMatches(fonts)) {
    final body = index.bodyOf(int.parse(match.group(2)!));
    if (body == null) continue;

    out[match.group(1)!] = _fontFrom(pdf, index, body);
  }

  return out;
}

PageFont _fontFrom(Uint8List pdf, PdfObjectIndex index, String font) {
  final toUnicode = RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(font);

  FontDecoder? decoder;

  if (toUnicode != null) {
    final cmap = streamContents(pdf, index, int.parse(toUnicode.group(1)!));
    if (cmap != null) {
      decoder = parseToUnicodeCMap(latin1.decode(cmap, allowInvalid: true));
    }
  }

  final descendant = RegExp(
    r'/DescendantFonts\s*\[\s*(\d+)\s+\d+\s+R',
  ).firstMatch(font);

  if (descendant != null) {
    // A composite font: the widths live on the descendant, keyed by glyph
    // identifier rather than by byte.
    final body = index.bodyOf(int.parse(descendant.group(1)!)) ?? '';

    return PageFont(
      decoder: decoder,
      widths: _compositeWidths(body),
      byCode:
          double.tryParse(
            RegExp(r'/DW\s+(-?[\d.]+)').firstMatch(body)?.group(1) ?? '',
          ) ??
          // ISO 32000-1 9.7.4.3: a composite font's default width is 1000
          // where it says nothing, which is an em - not zero.
          1000,
    );
  }

  decoder ??= simpleFontDecoder(
    baseEncoding: _baseEncoding(index, font),
    differences: _differences(index, font),
  );

  return PageFont(
    decoder: decoder,
    widths: _simpleWidths(font),
    byCode: double.tryParse(
      RegExp(r'/MissingWidth\s+(-?[\d.]+)').firstMatch(font)?.group(1) ?? '',
    ),
  );
}

/// `/FirstChar` and `/Widths`, which together say how wide each byte is.
Map<int, double> _simpleWidths(String font) {
  final first = int.tryParse(
    RegExp(r'/FirstChar\s+(\d+)').firstMatch(font)?.group(1) ?? '',
  );
  final widths = RegExp(r'/Widths\s*\[([^\]]*)\]').firstMatch(font);
  if (first == null || widths == null) return const {};

  final values = RegExp(r'-?[\d.]+')
      .allMatches(widths.group(1)!)
      .map((m) => double.tryParse(m.group(0)!) ?? 0)
      .toList();

  return {for (var i = 0; i < values.length; i++) first + i: values[i]};
}

/// `/W`, which states widths in two forms at once: a start code followed by a
/// list, or a range of codes followed by one width for all of them.
Map<int, double> _compositeWidths(String font) {
  final w = RegExp(
    r'/W\s*\[(.*?)\]\s*(?:/|>>|$)',
    dotAll: true,
  ).firstMatch(font);
  if (w == null) return const {};

  final out = <int, double>{};
  final source = w.group(1)!;

  for (final match in RegExp(r'(\d+)\s*\[([^\]]*)\]').allMatches(source)) {
    final start = int.parse(match.group(1)!);
    final values = RegExp(r'-?[\d.]+').allMatches(match.group(2)!).toList();

    for (var i = 0; i < values.length; i++) {
      out[start + i] = double.tryParse(values[i].group(0)!) ?? 0;
    }
  }

  // The range form, with the list form's contents removed first so its
  // numbers are not read as ranges.
  final ranges = source.replaceAll(RegExp(r'\d+\s*\[[^\]]*\]'), ' ');
  for (final match in RegExp(
    r'(\d+)\s+(\d+)\s+(-?[\d.]+)',
  ).allMatches(ranges)) {
    final from = int.parse(match.group(1)!);
    final to = int.parse(match.group(2)!);
    final width = double.tryParse(match.group(3)!) ?? 0;

    // A range covering the whole of a composite font's code space is a
    // damaged document, and filling a map from it is how a reader stops
    // responding.
    if (to < from || to - from > 0xFFFF) continue;

    for (var code = from; code <= to; code++) {
      out[code] = width;
    }
  }

  return out;
}

String? _baseEncoding(PdfObjectIndex index, String font) {
  final name = RegExp(r'/Encoding\s*/(\w+)').firstMatch(font);
  if (name != null) return name.group(1);

  final dictionary = _dictionaryFor(index, font, 'Encoding');
  return dictionary == null
      ? null
      : RegExp(r'/BaseEncoding\s*/(\w+)').firstMatch(dictionary)?.group(1);
}

String? _differences(PdfObjectIndex index, String font) {
  final dictionary = _dictionaryFor(index, font, 'Encoding');
  if (dictionary == null) return null;

  return RegExp(
    r'/Differences\s*\[([^\]]*)\]',
  ).firstMatch(dictionary)?.group(1);
}

/// A stream's contents, inflated where they are compressed.
///
/// Returns null for filters Folio does not decode, which is honest: a font map
/// that cannot be read makes its text uneditable rather than misread.
List<int>? streamContents(
  Uint8List pdf,
  PdfObjectIndex index,
  int objectNumber,
) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final object = RegExp(
    '(?<![0-9])$objectNumber 0 obj',
  ).allMatches(text).lastOrNull;
  if (object == null) return null;

  final start = text.indexOf('stream', object.end);
  if (start == -1) return null;

  final dictionary = text.substring(object.end, start);
  var from = start + 'stream'.length;
  if (from < pdf.length && pdf[from] == 0x0D) from++;
  if (from < pdf.length && pdf[from] == 0x0A) from++;

  final end = text.indexOf('endstream', from);
  if (end == -1) return null;

  var to = end;
  while (to > from && (pdf[to - 1] == 0x0A || pdf[to - 1] == 0x0D)) {
    to--;
  }

  final raw = pdf.sublist(from, to);

  if (!dictionary.contains('/Filter')) return raw;
  if (!dictionary.contains('/FlateDecode')) return null;

  try {
    return ZLibCodec().decode(raw);
  } on FormatException {
    return null;
  }
}

/// The value of an inheritable entry, walking `/Parent` until it is found.
String? _inherited(PdfObjectIndex index, String dictionary, String key) {
  var current = dictionary;

  for (var depth = 0; depth < 32; depth++) {
    final found = _dictionaryFor(index, current, key);
    if (found != null) return found;

    final parent = RegExp(r'/Parent\s+(\d+)\s+\d+\s+R').firstMatch(current);
    if (parent == null) return null;

    final next = index.bodyOf(int.parse(parent.group(1)!));
    if (next == null) return null;
    current = next;
  }

  return null;
}

/// The dictionary [key] holds, whether written inline or as a reference.
String? _dictionaryFor(PdfObjectIndex index, String dictionary, String key) {
  final reference = RegExp(
    '/$key'
    r'\s+(\d+)\s+\d+\s+R',
  ).firstMatch(dictionary);
  if (reference != null) return index.bodyOf(int.parse(reference.group(1)!));

  final inline = RegExp(
    '/$key'
    r'\s*<<',
  ).firstMatch(dictionary);
  if (inline == null) return null;

  final close = PdfObjectIndex.matchingClose(dictionary, inline.end - 2);
  if (close < 0) return null;

  return dictionary.substring(
    inline.end - 2,
    (close + 2).clamp(0, dictionary.length),
  );
}
