import 'dart:typed_data';

import 'package:folio/domain/fonts/truetype_font.dart';

/// The tables a subset keeps.
///
/// Enough for a CIDFontType2 with an identity glyph mapping, which is what
/// Folio embeds: the PDF addresses glyphs by index, so the font's own `cmap`
/// is never consulted and would be the largest thing in the file. `name`,
/// `post` and the hinting tables go the same way.
const _kept = ['head', 'hhea', 'maxp', 'hmtx', 'loca', 'glyf'];

/// A font carrying only [glyphs] and what they are built from.
///
/// Embedding a whole font makes a fifty-kilobyte document into a
/// six-hundred-kilobyte one, for the sake of a dozen letters. This keeps the
/// glyph INDICES unchanged and empties the outlines of everything unused,
/// which means nothing else in the font has to be renumbered - no `cmap` to
/// rebuild, no metrics to re-index, and one fewer thing to get wrong.
Uint8List subsetFont(TrueTypeFont font, Set<int> glyphs) {
  // Glyph zero draws the "missing character" box. It has to survive, because
  // a reader asked for a glyph that is not there will reach for it.
  final wanted = <int>{0, ...glyphs.where((g) => g >= 0 && g < font.numGlyphs)};
  for (final glyph in {...wanted}) {
    wanted.addAll(font.componentsOf(glyph));
  }

  final glyf = font.tables['glyf']!.offset;
  final outlines = <int>[];
  final offsets = <int>[];

  for (var glyph = 0; glyph < font.numGlyphs; glyph++) {
    offsets.add(outlines.length);
    if (!wanted.contains(glyph)) continue;

    final range = font.glyphRange(glyph);
    if (range.end <= range.start) continue;

    outlines.addAll(font.bytes.sublist(glyf + range.start, glyf + range.end));
    while (outlines.length % 4 != 0) {
      outlines.add(0);
    }
  }
  offsets.add(outlines.length);

  // Long offsets, always. Short ones store half the offset, so a subset whose
  // glyf table happens to be odd-sized cannot be expressed in them at all.
  final loca = <int>[];
  for (final offset in offsets) {
    loca.addAll([
      (offset >> 24) & 0xFF,
      (offset >> 16) & 0xFF,
      (offset >> 8) & 0xFF,
      offset & 0xFF,
    ]);
  }

  final tables = <String, List<int>>{};
  for (final tag in _kept) {
    final table = font.tables[tag];
    if (table == null) continue;

    tables[tag] = switch (tag) {
      'glyf' => outlines,
      'loca' => loca,
      'head' => _patchedHead(font, table),
      _ => font.bytes.sublist(table.offset, table.offset + table.length),
    };
  }

  return _assemble(tables);
}

/// `head` with the offset format switched to long, and the whole-file checksum
/// cleared.
///
/// The checksum covers a file that no longer exists. Leaving the old value is
/// worse than leaving none: a reader that checks it rejects the font, and one
/// that does not was never going to look.
List<int> _patchedHead(TrueTypeFont font, ({int offset, int length}) table) {
  final head = Uint8List.fromList(
    font.bytes.sublist(table.offset, table.offset + table.length),
  );
  final data = ByteData.sublistView(head);

  data.setUint32(8, 0); // checkSumAdjustment
  data.setInt16(50, 1); // indexToLocFormat: long

  return head;
}

/// Table directory and tables, in the order a TrueType file wants them.
Uint8List _assemble(Map<String, List<int>> tables) {
  final tags = tables.keys.toList()..sort();
  final out = <int>[];

  // The offset table's search values are derived from the table count. They
  // are advisory - a reader may binary-search with them - but a font whose
  // values contradict its count is malformed.
  var entrySelector = 0;
  while ((1 << (entrySelector + 1)) <= tags.length) {
    entrySelector++;
  }
  final searchRange = (1 << entrySelector) * 16;

  out
    ..addAll(_uint32(0x00010000))
    ..addAll(_uint16(tags.length))
    ..addAll(_uint16(searchRange))
    ..addAll(_uint16(entrySelector))
    ..addAll(_uint16(tags.length * 16 - searchRange));

  var offset = 12 + tags.length * 16;
  final placement = <String, ({int offset, int length})>{};

  for (final tag in tags) {
    final length = tables[tag]!.length;
    placement[tag] = (offset: offset, length: length);
    offset += length;
    while (offset % 4 != 0) {
      offset++;
    }
  }

  for (final tag in tags) {
    out
      ..addAll(tag.codeUnits)
      ..addAll(_uint32(_checksum(tables[tag]!)))
      ..addAll(_uint32(placement[tag]!.offset))
      ..addAll(_uint32(placement[tag]!.length));
  }

  for (final tag in tags) {
    out.addAll(tables[tag]!);
    while (out.length % 4 != 0) {
      out.add(0);
    }
  }

  return Uint8List.fromList(out);
}

/// A table's checksum: the sum of its 32-bit words, padded with zeroes.
int _checksum(List<int> table) {
  var sum = 0;
  for (var i = 0; i < table.length; i += 4) {
    sum =
        (sum +
            ((table[i] << 24) |
                (i + 1 < table.length ? table[i + 1] << 16 : 0) |
                (i + 2 < table.length ? table[i + 2] << 8 : 0) |
                (i + 3 < table.length ? table[i + 3] : 0))) &
        0xFFFFFFFF;
  }
  return sum;
}

List<int> _uint16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

List<int> _uint32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];
