import 'dart:typed_data';

/// Builds a tiny TrueType font with whatever awkward choices a test needs.
///
/// The shipped font is comfortable in every way that matters: a 1000-unit
/// grid, long glyph offsets, a metric for every glyph, and a character map
/// with no indirection in it. Every one of those is a code path in the parser
/// that a test using only that font can never reach - and four separate
/// mutations survived because of it.
///
/// Glyphs: 0 .notdef, 1 'A', 2 'B', 3 a composite of 2, 4 a composite of 3,
/// 5 and 6 with no metric of their own.
Uint8List syntheticFont({
  int unitsPerEm = 2048,
  bool longLoca = false,
  bool withFormat12 = false,
  bool withRangeOffset = true,
}) {
  const numGlyphs = 7;
  const numberOfHMetrics = 5;

  final glyphs = <List<int>>[
    _simpleGlyph(),
    _simpleGlyph(),
    _simpleGlyph(),
    _compositeGlyph(2),
    _compositeGlyph(3),
    _simpleGlyph(),
    <int>[], // an empty glyph, like a space
  ];

  final glyf = <int>[];
  final offsets = <int>[];
  for (final glyph in glyphs) {
    offsets.add(glyf.length);
    glyf.addAll(glyph);
    while (glyf.length % 4 != 0) {
      glyf.add(0);
    }
  }
  offsets.add(glyf.length);

  final loca = <int>[];
  for (final offset in offsets) {
    // The short form stores HALF the offset, which is why it needs even ones.
    loca.addAll(longLoca ? _u32(offset) : _u16(offset ~/ 2));
  }

  final head = List<int>.filled(54, 0);
  _put16(head, 18, unitsPerEm);
  _put16(head, 36, 0); // xMin
  _put16(head, 38, 0); // yMin
  _put16(head, 40, unitsPerEm);
  _put16(head, 42, unitsPerEm);
  _put16(head, 50, longLoca ? 1 : 0);

  final hhea = List<int>.filled(36, 0);
  _put16(hhea, 4, (unitsPerEm * 0.75).round()); // ascender
  _put16(hhea, 6, 0x10000 - (unitsPerEm * 0.25).round()); // descender
  _put16(hhea, 34, numberOfHMetrics);

  final maxp = List<int>.filled(32, 0);
  _put16(maxp, 0, 1); // version 1.0
  _put16(maxp, 4, numGlyphs);

  // Widths climb with the glyph index, so a glyph past the array is easy to
  // tell from one inside it.
  final hmtx = <int>[];
  for (var i = 0; i < numberOfHMetrics; i++) {
    hmtx
      ..addAll(_u16(100 + i * 100))
      ..addAll(_u16(0));
  }
  for (var i = numberOfHMetrics; i < numGlyphs; i++) {
    hmtx.addAll(_u16(0));
  }

  return _assemble({
    'head': head,
    'hhea': hhea,
    'maxp': maxp,
    'hmtx': hmtx,
    'loca': loca,
    'glyf': glyf,
    'cmap': _cmap(withFormat12: withFormat12, withRangeOffset: withRangeOffset),
  });
}

/// 'A' maps through a plain delta; 'B' and 'C' map through the glyph array.
///
/// The indirecting segment is deliberately the SECOND one. idRangeOffset is
/// measured from the position of its own entry, and with the indirection in
/// the first segment that offset happens to equal the one measured from the
/// start of the array - so the classic mistake produces the right answer and
/// no test can see it.
List<int> _cmap({required bool withFormat12, required bool withRangeOffset}) {
  final format4 = <int>[];
  const segments = 3;

  format4
    ..addAll(_u16(4))
    ..addAll(_u16(0)) // length, patched below
    ..addAll(_u16(0)) // language
    ..addAll(_u16(segments * 2))
    ..addAll(_u16(4))
    ..addAll(_u16(1))
    ..addAll(_u16(segments * 2 - 4))
    // endCode
    ..addAll(_u16(0x41))
    ..addAll(_u16(0x43))
    ..addAll(_u16(0xFFFF))
    ..addAll(_u16(0)) // reservedPad
    // startCode
    ..addAll(_u16(0x41))
    ..addAll(_u16(0x42))
    ..addAll(_u16(0xFFFF));

  // idDelta: 'A' + delta = 3.
  format4
    ..addAll(_u16(0x10000 + 3 - 0x41))
    ..addAll(_u16(withRangeOffset ? 0 : 0x10000 + 2 - 0x42))
    ..addAll(_u16(1));

  // idRangeOffset. The second entry sits two bytes into the array, and the
  // glyph array begins six bytes in, so the offset from the entry is four.
  format4
    ..addAll(_u16(0))
    ..addAll(_u16(withRangeOffset ? 4 : 0))
    ..addAll(_u16(0))
    // glyphIdArray: 'B' -> 2, 'C' -> 4
    ..addAll(_u16(2))
    ..addAll(_u16(4));

  _put16(format4, 2, format4.length);

  final tables = <({int platform, int encoding, List<int> data})>[
    (platform: 3, encoding: 1, data: format4),
    if (withFormat12)
      (
        platform: 3,
        encoding: 10,
        // 'A' maps to glyph 5 here, so which subtable was read is visible.
        data: [
          ..._u16(12),
          ..._u16(0),
          ..._u32(16 + 12),
          ..._u32(0),
          ..._u32(1),
          ..._u32(0x41),
          ..._u32(0x41),
          ..._u32(5),
        ],
      ),
  ];

  final out = <int>[..._u16(0), ..._u16(tables.length)];
  var offset = 4 + tables.length * 8;

  for (final table in tables) {
    out
      ..addAll(_u16(table.platform))
      ..addAll(_u16(table.encoding))
      ..addAll(_u32(offset));
    offset += table.data.length;
  }
  for (final table in tables) {
    out.addAll(table.data);
  }

  return out;
}

List<int> _simpleGlyph() => [
  ..._u16(1), // one contour
  ..._u16(0), ..._u16(0), ..._u16(100), ..._u16(100),
  ..._u16(0), // endPtsOfContours
  ..._u16(0), // instruction length
  0x01, // flags: on curve
  10, 10, // coordinates
];

/// A composite referring to [component], with no further parts.
List<int> _compositeGlyph(int component) => [
  ..._u16(0xFFFF), // -1: composite
  ..._u16(0), ..._u16(0), ..._u16(100), ..._u16(100),
  ..._u16(0x0001), // ARG_1_AND_2_ARE_WORDS, no MORE_COMPONENTS
  ..._u16(component),
  ..._u16(0), ..._u16(0),
];

Uint8List _assemble(Map<String, List<int>> tables) {
  final tags = tables.keys.toList()..sort();
  final out = <int>[
    ..._u32(0x00010000),
    ..._u16(tags.length),
    ..._u16(0),
    ..._u16(0),
    ..._u16(0),
  ];

  var offset = 12 + tags.length * 16;
  final placement = <String, int>{};

  for (final tag in tags) {
    placement[tag] = offset;
    offset += tables[tag]!.length;
    while (offset % 4 != 0) {
      offset++;
    }
  }

  for (final tag in tags) {
    out
      ..addAll(tag.codeUnits)
      ..addAll(_u32(0))
      ..addAll(_u32(placement[tag]!))
      ..addAll(_u32(tables[tag]!.length));
  }

  for (final tag in tags) {
    out.addAll(tables[tag]!);
    while (out.length % 4 != 0) {
      out.add(0);
    }
  }

  return Uint8List.fromList(out);
}

List<int> _u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

List<int> _u32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

void _put16(List<int> bytes, int at, int value) {
  bytes[at] = (value >> 8) & 0xFF;
  bytes[at + 1] = value & 0xFF;
}
