import 'dart:convert';
import 'dart:io';

import 'package:folio/domain/fonts/truetype_font.dart';
import 'package:folio/domain/fonts/truetype_subset.dart';

/// One PDF object: its number and its body.
typedef FontObject = ({int number, List<int> body});

/// A font on its way into a PDF.
///
/// Collect the text to be drawn with [encode], then ask for [objects]. The
/// subset carries exactly the glyphs that were encoded, so the font added to a
/// document is a few kilobytes rather than half a megabyte.
///
/// The encoding is Identity-H: two bytes per glyph, addressing the font by
/// glyph index. That is what lets any character be written - a single-byte
/// encoding can carry 256 of them, and the rupee sign is not among the 256
/// anybody chose.
class EmbeddedFont {
  EmbeddedFont(this.font, {this.baseName = 'NotoSans'});

  final TrueTypeFont font;
  final String baseName;

  /// Glyph index to the character it was written for, which is what a
  /// `/ToUnicode` map needs to let the text be selected and copied.
  final Map<int, int> _used = {};

  bool get isEmpty => _used.isEmpty;

  /// [text] as a hex string of glyph indices, with its width in thousandths
  /// of the text size.
  ///
  /// Characters the font has no glyph for are reported rather than replaced.
  /// Drawing glyph zero for them puts a row of boxes on the page, which looks
  /// like a broken document rather than a missing character.
  ({String hex, double width, List<int> missing}) encode(String text) {
    final buffer = StringBuffer();
    final missing = <int>[];
    var width = 0.0;

    for (final rune in text.runes) {
      final glyph = font.glyphFor(rune);
      if (glyph == null) {
        missing.add(rune);
        continue;
      }

      _used[glyph] = rune;
      buffer.write(glyph.toRadixString(16).padLeft(4, '0').toUpperCase());
      width += font.advanceWidth(glyph) * 1000 / font.unitsPerEm;
    }

    return (hex: buffer.toString(), width: width, missing: missing);
  }

  /// The width of [text] in thousandths, without recording its glyphs.
  double measure(String text) {
    var width = 0.0;
    for (final rune in text.runes) {
      final glyph = font.glyphFor(rune);
      if (glyph != null) {
        width += font.advanceWidth(glyph) * 1000 / font.unitsPerEm;
      }
    }
    return width;
  }

  /// The objects to add, numbered from [first]. The FIRST is the font a page's
  /// resources should point at; the rest are what it depends on.
  List<FontObject> objects(int first) {
    final descendant = first + 1;
    final descriptor = first + 2;
    final file = first + 3;
    final toUnicode = first + 4;
    final name = '${_prefix()}+$baseName';

    final subset = subsetFont(font, _used.keys.toSet());
    final compressed = ZLibCodec(level: 9).encode(subset);
    final unicode = latin1.encode(_toUnicodeCMap());
    final compressedUnicode = ZLibCodec(level: 9).encode(unicode);

    return [
      (
        number: first,
        body: latin1.encode(
          '<< /Type /Font /Subtype /Type0 /BaseFont /$name '
          '/Encoding /Identity-H /DescendantFonts [$descendant 0 R] '
          '/ToUnicode $toUnicode 0 R >>',
        ),
      ),
      (
        number: descendant,
        body: latin1.encode(
          '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /$name '
          '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
          '/Supplement 0 >> /FontDescriptor $descriptor 0 R '
          '/DW 1000 /W ${_widths()} /CIDToGIDMap /Identity >>',
        ),
      ),
      (
        number: descriptor,
        body: latin1.encode(
          '<< /Type /FontDescriptor /FontName /$name /Flags ${_flags()} '
          '/FontBBox [${_scale(font.bounds.minX)} ${_scale(font.bounds.minY)} '
          '${_scale(font.bounds.maxX)} ${_scale(font.bounds.maxY)}] '
          '/ItalicAngle ${font.italicAngle.round()} '
          '/Ascent ${_scale(font.ascender)} '
          '/Descent ${_scale(font.descender)} '
          '/CapHeight ${_scale(font.capHeight)} '
          // TrueType records no stem width. Eighty is the conventional stand-in
          // for a regular weight, and it is only consulted when a reader has to
          // synthesise a substitute - which, the font being carried, it will
          // not.
          '/StemV 80 /FontFile2 $file 0 R >>',
        ),
      ),
      (
        number: file,
        body: [
          // /Length1 is the size before compression, and a reader that trusts
          // it will read exactly that many bytes back out.
          ...latin1.encode(
            '<< /Length ${compressed.length} /Length1 ${subset.length} '
            '/Filter /FlateDecode >>\nstream\n',
          ),
          ...compressed,
          ...latin1.encode('\nendstream'),
        ],
      ),
      (
        number: toUnicode,
        body: [
          ...latin1.encode(
            '<< /Length ${compressedUnicode.length} /Filter /FlateDecode '
            '>>\nstream\n',
          ),
          ...compressedUnicode,
          ...latin1.encode('\nendstream'),
        ],
      ),
    ];
  }

  /// How many objects [objects] returns, for a caller reserving numbers.
  static const objectCount = 5;

  int _flags() =>
      (font.isFixedPitch ? 1 : 0) |
      // Symbolic: the font is addressed by glyph index rather than through a
      // standard encoding, so a reader must not assume one.
      4 |
      (font.italicAngle != 0 ? 64 : 0);

  int _scale(int units) => (units * 1000 / font.unitsPerEm).round();

  /// `/W`, as runs of consecutive glyphs sharing one list of widths.
  String _widths() {
    final glyphs = _used.keys.toList()..sort();
    final buffer = StringBuffer('[');

    for (var i = 0; i < glyphs.length;) {
      var end = i;
      while (end + 1 < glyphs.length && glyphs[end + 1] == glyphs[end] + 1) {
        end++;
      }

      buffer.write('${glyphs[i]} [');
      for (var j = i; j <= end; j++) {
        buffer.write(j == i ? '' : ' ');
        buffer.write(_scale(font.advanceWidth(glyphs[j])));
      }
      buffer.write(']');

      i = end + 1;
    }

    return (buffer..write(']')).toString();
  }

  /// The map from glyph index back to character.
  ///
  /// Without it a reader can draw the text and nothing else: no selecting, no
  /// copying, no searching, and no extraction - which is how a document ends
  /// up looking like a scan of itself.
  String _toUnicodeCMap() {
    final glyphs = _used.keys.toList()..sort();
    final buffer = StringBuffer()
      ..writeln('/CIDInit /ProcSet findresource begin')
      ..writeln('12 dict begin')
      ..writeln('begincmap')
      ..writeln(
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) '
        '/Supplement 0 >> def',
      )
      ..writeln('/CMapName /Adobe-Identity-UCS def')
      ..writeln('/CMapType 2 def')
      ..writeln('1 begincodespacerange')
      ..writeln('<0000> <FFFF>')
      ..writeln('endcodespacerange');

    // A hundred entries is the most a single block may hold.
    for (var start = 0; start < glyphs.length; start += 100) {
      final block = glyphs.skip(start).take(100).toList();
      buffer.writeln('${block.length} beginbfchar');

      for (final glyph in block) {
        buffer.writeln('<${_hex4(glyph)}> <${_utf16Hex(_used[glyph]!)}>');
      }

      buffer.writeln('endbfchar');
    }

    return (buffer
          ..writeln('endcmap')
          ..writeln('CMapName currentdict /CMap defineresource pop')
          ..writeln('end')
          ..writeln('end'))
        .toString();
  }

  /// Six letters identifying this subset, derived from the glyphs in it.
  ///
  /// PDF requires the tag so two subsets of one font are not mistaken for each
  /// other. Derived rather than random, so converting the same document twice
  /// gives the same bytes.
  String _prefix() {
    var hash = 0;
    for (final glyph in _used.keys.toList()..sort()) {
      hash = (hash * 31 + glyph) & 0x7FFFFFFF;
    }

    final letters = StringBuffer();
    for (var i = 0; i < 6; i++) {
      letters.writeCharCode(65 + (hash % 26));
      hash ~/= 26;
    }
    return letters.toString();
  }

  String _hex4(int value) =>
      value.toRadixString(16).padLeft(4, '0').toUpperCase();

  /// A code point as UTF-16, which is what a `/ToUnicode` value holds.
  /// Anything above the basic plane needs a surrogate pair.
  String _utf16Hex(int rune) {
    if (rune <= 0xFFFF) return _hex4(rune);

    final adjusted = rune - 0x10000;
    return '${_hex4(0xD800 + (adjusted >> 10))}'
        '${_hex4(0xDC00 + (adjusted & 0x3FF))}';
  }
}
