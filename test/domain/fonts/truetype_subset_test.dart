import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/fonts/truetype_font.dart';
import 'package:folio/domain/fonts/truetype_subset.dart';

void main() {
  late TrueTypeFont font;

  setUpAll(
    () => font = TrueTypeFont.parse(
      File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync(),
    ),
  );

  Set<int> glyphsFor(String text) => {
    for (final rune in text.runes)
      if (font.glyphFor(rune) != null) font.glyphFor(rune)!,
  };

  /// The subset, read back by the same parser - which is fair here, because
  /// what is being checked is that the result is a font at all.
  TrueTypeFont subsetFor(String text) =>
      TrueTypeFont.parse(subsetFont(font, glyphsFor(text)));

  group('the result is a font', () {
    test('it parses', () {
      expect(() => subsetFor('Hello'), returnsNormally);
    });

    test('it keeps the tables a reader needs', () {
      expect(
        subsetFor('Hello').tables.keys,
        containsAll(['head', 'hhea', 'maxp', 'hmtx', 'loca', 'glyf']),
      );
    });

    test('every table lies inside the file', () {
      final subset = subsetFor('Hello');

      for (final table in subset.tables.entries) {
        expect(
          table.value.offset + table.value.length,
          lessThanOrEqualTo(subset.bytes.length),
          reason: table.key,
        );
      }
    });

    // Tables must begin on four-byte boundaries.
    test('every table begins on a four-byte boundary', () {
      final subset = subsetFor('Hello');

      for (final table in subset.tables.entries) {
        expect(table.value.offset % 4, 0, reason: table.key);
      }
    });

    test('it keeps the same glyph count and design grid', () {
      final subset = subsetFor('Hello');

      expect(subset.numGlyphs, font.numGlyphs);
      expect(subset.unitsPerEm, font.unitsPerEm);
    });

    // The indices do not move, which is the whole point: nothing else in the
    // font has to be renumbered.
    test('a letter keeps the glyph index it had', () {
      expect(
        subsetFor('Hello').glyphRange(font.glyphFor(0x48)!).end,
        greaterThan(0),
      );
    });
  });

  group('what it keeps', () {
    test('the letters asked for still have outlines', () {
      final subset = subsetFor('Hello');

      for (final rune in 'Helo'.runes) {
        final range = subset.glyphRange(font.glyphFor(rune)!);
        expect(
          range.end,
          greaterThan(range.start),
          reason: 'U+${rune.toRadixString(16)}',
        );
      }
    });

    test('a letter not asked for has no outline left', () {
      final subset = subsetFor('Hello');
      final range = subset.glyphRange(font.glyphFor(0x5A)!); // Z

      expect(range.end, range.start);
    });

    // Glyph zero draws the missing-character box. A reader asked for a glyph
    // that is not there reaches for it.
    test('glyph zero survives even when nobody asked for it', () {
      final range = subsetFor('Hello').glyphRange(0);

      expect(range.end, greaterThan(range.start));
    });

    // An accented letter is a base and a mark referenced by index. Keeping
    // the composite and dropping its components draws nothing at all.
    test('a composite letter keeps the glyphs it is built from', () {
      final subset = subsetFor('é');
      final components = font.componentsOf(font.glyphFor(0xE9)!);

      expect(components, isNotEmpty);
      for (final component in components) {
        final range = subset.glyphRange(component);
        expect(range.end, greaterThan(range.start), reason: 'glyph $component');
      }
    });

    test('widths are unchanged', () {
      final subset = subsetFor('Hello');
      final glyph = font.glyphFor(0x48)!;

      expect(subset.advanceWidth(glyph), font.advanceWidth(glyph));
    });
  });

  group('what it drops', () {
    // The point of the exercise. Embedding the whole font makes a fifty
    // kilobyte document into a six hundred kilobyte one.
    test('the subset is a fraction of the size', () {
      final subset = subsetFont(font, glyphsFor('Hello, Priya'));

      expect(subset.length, lessThan(font.bytes.length ~/ 10));
    });

    test('a bigger alphabet gives a bigger subset', () {
      final small = subsetFont(font, glyphsFor('ab'));
      final large = subsetFont(
        font,
        glyphsFor('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'),
      );

      expect(large.length, greaterThan(small.length));
    });

    // The PDF addresses glyphs by index, so the font's own character map is
    // never consulted - and in Noto it is the largest thing left.
    test('the character map is not carried', () {
      expect(subsetFor('Hello').tables.containsKey('cmap'), isFalse);
    });
  });

  group('the offset table', () {
    // The offsets are long in a subset, whatever they were before: short ones
    // store half the offset and cannot express an odd-sized glyf table.
    test('declares long glyph offsets', () {
      expect(subsetFor('Hello').indexToLocFormat, 1);
    });

    test('there is one offset more than there are glyphs', () {
      final subset = subsetFor('Hello');

      expect(subset.tables['loca']!.length, (subset.numGlyphs + 1) * 4);
    });

    test('offsets never go backwards', () {
      final subset = subsetFor('Hello');
      var previous = 0;

      for (var glyph = 0; glyph < subset.numGlyphs; glyph++) {
        final range = subset.glyphRange(glyph);
        expect(range.start, greaterThanOrEqualTo(previous));
        previous = range.end;
      }
    });

    // The whole-file checksum covers a file that no longer exists.
    test('the stale whole-file checksum is cleared', () {
      final subset = subsetFor('Hello');
      final head = subset.tables['head']!.offset;

      expect(ByteData.sublistView(subset.bytes).getUint32(head + 8), 0);
    });
  });
}
