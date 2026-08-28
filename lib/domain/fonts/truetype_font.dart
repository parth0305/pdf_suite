import 'dart:typed_data';

/// A TrueType font, read far enough to embed it in a PDF.
///
/// Not a rendering engine: this reads the metrics a PDF font dictionary needs,
/// the character-to-glyph mapping needed to write text, and enough of the
/// glyph outlines to subset them. Everything else in the file is left alone.
class TrueTypeFont {
  TrueTypeFont._({
    required this.bytes,
    required this.tables,
    required this.unitsPerEm,
    required this.numGlyphs,
    required this.indexToLocFormat,
    required this.ascender,
    required this.descender,
    required this.capHeight,
    required this.italicAngle,
    required this.isFixedPitch,
    required this.bounds,
    required this.numberOfHMetrics,
    required Map<int, int> characters,
  }) : _characters = characters;

  final Uint8List bytes;

  /// Where each table starts and how long it is, by its four-letter tag.
  final Map<String, ({int offset, int length})> tables;

  /// The design grid. Glyph coordinates are in these units and PDF wants
  /// thousandths of the text size, so everything scales by 1000/unitsPerEm.
  final int unitsPerEm;

  final int numGlyphs;
  final int indexToLocFormat;
  final int ascender;
  final int descender;
  final int capHeight;
  final double italicAngle;
  final bool isFixedPitch;
  final ({int minX, int minY, int maxX, int maxY}) bounds;
  final int numberOfHMetrics;

  final Map<int, int> _characters;

  static TrueTypeFont parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final numTables = data.getUint16(4);
    final tables = <String, ({int offset, int length})>{};

    for (var i = 0; i < numTables; i++) {
      final at = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(at, at + 4));
      tables[tag] = (
        offset: data.getUint32(at + 8),
        length: data.getUint32(at + 12),
      );
    }

    for (final required in ['head', 'hhea', 'maxp', 'hmtx', 'glyf', 'loca']) {
      if (!tables.containsKey(required)) {
        throw ArgumentError.value(required, 'font', 'table is missing');
      }
    }

    final head = tables['head']!.offset;
    final hhea = tables['hhea']!.offset;
    final maxp = tables['maxp']!.offset;
    final os2 = tables['OS/2']?.offset;
    final post = tables['post']?.offset;

    return TrueTypeFont._(
      bytes: bytes,
      tables: tables,
      unitsPerEm: data.getUint16(head + 18),
      numGlyphs: data.getUint16(maxp + 4),
      indexToLocFormat: data.getInt16(head + 50),
      ascender: data.getInt16(hhea + 4),
      descender: data.getInt16(hhea + 6),
      // Only OS/2 version 2 and later carry a cap height. Two thirds of the
      // ascender is the conventional stand-in, and it only affects how a
      // reader substitutes a missing font - which, the font being carried, it
      // will not have to do.
      capHeight: os2 != null && data.getUint16(os2) >= 2
          ? data.getInt16(os2 + 88)
          : (data.getInt16(hhea + 4) * 2) ~/ 3,
      italicAngle: post == null ? 0 : data.getInt32(post + 4) / 65536,
      isFixedPitch: post != null && data.getUint32(post + 12) != 0,
      bounds: (
        minX: data.getInt16(head + 36),
        minY: data.getInt16(head + 38),
        maxX: data.getInt16(head + 40),
        maxY: data.getInt16(head + 42),
      ),
      numberOfHMetrics: data.getUint16(hhea + 34),
      characters: tables.containsKey('cmap')
          ? _readCmap(data, tables['cmap']!.offset)
          : const {},
    );
  }

  /// The glyph for [codePoint], or null when the font has none.
  ///
  /// Null is not a failure to swallow: drawing glyph 0 puts a box on the page
  /// where a letter should be, which is worse than saying so.
  int? glyphFor(int codePoint) => _characters[codePoint];

  /// The advance width of [glyph], in font units.
  ///
  /// Glyphs past `numberOfHMetrics` share the last width - that is how a
  /// monospaced tail is stored, and reading past the array is how a parser
  /// crashes on one.
  int advanceWidth(int glyph) {
    final hmtx = tables['hmtx']!.offset;
    final data = ByteData.sublistView(bytes);
    final index = glyph < numberOfHMetrics ? glyph : numberOfHMetrics - 1;
    return data.getUint16(hmtx + index * 4);
  }

  /// Where glyph [index]'s outline sits in the `glyf` table.
  ({int start, int end}) glyphRange(int index) {
    final loca = tables['loca']!.offset;
    final data = ByteData.sublistView(bytes);

    if (indexToLocFormat == 0) {
      return (
        start: data.getUint16(loca + index * 2) * 2,
        end: data.getUint16(loca + index * 2 + 2) * 2,
      );
    }
    return (
      start: data.getUint32(loca + index * 4),
      end: data.getUint32(loca + index * 4 + 4),
    );
  }

  /// The glyphs a composite glyph is built from, recursively.
  ///
  /// An accented letter is usually a base and a mark referenced by index. A
  /// subset that keeps the composite and drops its components draws nothing.
  Set<int> componentsOf(int index, {int depth = 0}) {
    if (depth > 5) return const {};

    final range = glyphRange(index);
    if (range.end <= range.start) return const {};

    final data = ByteData.sublistView(bytes);
    final glyf = tables['glyf']!.offset;
    if (data.getInt16(glyf + range.start) >= 0) return const {};

    final out = <int>{};
    var at = glyf + range.start + 10;

    while (true) {
      final flags = data.getUint16(at);
      final component = data.getUint16(at + 2);
      out
        ..add(component)
        ..addAll(componentsOf(component, depth: depth + 1));

      at += 4;
      // ARG_1_AND_2_ARE_WORDS
      at += (flags & 0x0001) != 0 ? 4 : 2;
      if ((flags & 0x0008) != 0) {
        at += 2; // WE_HAVE_A_SCALE
      } else if ((flags & 0x0040) != 0) {
        at += 4; // X_AND_Y_SCALE
      } else if ((flags & 0x0080) != 0) {
        at += 8; // TWO_BY_TWO
      }

      // MORE_COMPONENTS
      if ((flags & 0x0020) == 0) break;
    }

    return out;
  }
}

/// Character to glyph, from whichever `cmap` subtable is the most capable.
///
/// Format 12 covers everything above the basic plane; format 4 covers the
/// basic plane and is what most fonts carry. Preferring 4 when both exist
/// silently loses every character above U+FFFF.
Map<int, int> _readCmap(ByteData data, int cmap) {
  final numTables = data.getUint16(cmap + 2);
  int? best;
  var bestScore = -1;

  for (var i = 0; i < numTables; i++) {
    final at = cmap + 4 + i * 8;
    final platform = data.getUint16(at);
    final encoding = data.getUint16(at + 2);
    final offset = cmap + data.getUint32(at + 4);
    final format = data.getUint16(offset);

    final score = switch ((platform, encoding, format)) {
      (3, 10, 12) => 4,
      (0, _, 12) => 3,
      (3, 1, 4) => 2,
      (0, _, 4) => 1,
      _ => -1,
    };

    if (score > bestScore) {
      bestScore = score;
      best = offset;
    }
  }

  if (best == null) return const {};

  return data.getUint16(best) == 12
      ? _readFormat12(data, best)
      : _readFormat4(data, best);
}

Map<int, int> _readFormat4(ByteData data, int at) {
  final segments = data.getUint16(at + 6) ~/ 2;
  final endCodes = at + 14;
  final startCodes = endCodes + segments * 2 + 2;
  final deltas = startCodes + segments * 2;
  final rangeOffsets = deltas + segments * 2;
  final out = <int, int>{};

  for (var s = 0; s < segments; s++) {
    final end = data.getUint16(endCodes + s * 2);
    final start = data.getUint16(startCodes + s * 2);
    final delta = data.getInt16(deltas + s * 2);
    final rangeOffset = data.getUint16(rangeOffsets + s * 2);
    if (start > end) continue;

    for (var code = start; code <= end && code != 0xFFFF; code++) {
      int glyph;
      if (rangeOffset == 0) {
        glyph = (code + delta) & 0xFFFF;
      } else {
        // The offset is measured from the position of the entry itself, which
        // is the one piece of format 4 everybody gets wrong once.
        final glyphAt = rangeOffsets + s * 2 + rangeOffset + (code - start) * 2;
        if (glyphAt + 1 >= data.lengthInBytes) continue;
        glyph = data.getUint16(glyphAt);
        if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
      }
      if (glyph != 0) out[code] = glyph;
    }
  }

  return out;
}

Map<int, int> _readFormat12(ByteData data, int at) {
  final groups = data.getUint32(at + 12);
  final out = <int, int>{};

  for (var g = 0; g < groups; g++) {
    final record = at + 16 + g * 12;
    final start = data.getUint32(record);
    final end = data.getUint32(record + 4);
    final glyph = data.getUint32(record + 8);

    // A damaged font can declare an enormous range. Mapping it would hang
    // rather than fail.
    if (end - start > 0x10000) continue;

    for (var code = start; code <= end; code++) {
      out[code] = glyph + (code - start);
    }
  }

  return out;
}
