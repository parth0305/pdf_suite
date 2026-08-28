import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/fonts/truetype_font.dart';

Uint8List load() => File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();

void main() {
  late TrueTypeFont font;

  setUpAll(() => font = TrueTypeFont.parse(load()));

  group('tables', () {
    test('finds the tables a PDF needs', () {
      expect(
        font.tables.keys,
        containsAll(['head', 'hhea', 'maxp', 'hmtx', 'glyf', 'loca', 'cmap']),
      );
    });

    test('every table lies inside the file', () {
      for (final table in font.tables.entries) {
        expect(
          table.value.offset + table.value.length,
          lessThanOrEqualTo(font.bytes.length),
          reason: table.key,
        );
      }
    });

    test('a font missing a table it needs is refused', () {
      final broken = Uint8List.fromList(load());
      // Rename 'glyf' to something no reader looks for.
      final at = _tagOffset(broken, 'glyf');
      broken.setRange(at, at + 4, 'xxxx'.codeUnits);

      expect(() => TrueTypeFont.parse(broken), throwsArgumentError);
    });
  });

  group('metrics', () {
    // PDF wants thousandths of the text size, so every measurement divides
    // by this. Reading it as a constant is how a font on a 1000 or 2048 grid
    // comes out at the wrong size.
    test('reads the design grid', () {
      expect(font.unitsPerEm, greaterThan(0));
      expect(1000 / font.unitsPerEm, lessThan(2));
    });

    test('reads a plausible glyph count', () {
      expect(font.numGlyphs, greaterThan(200));
    });

    test('the ascender is above the baseline and the descender below', () {
      expect(font.ascender, greaterThan(0));
      expect(font.descender, lessThan(0));
    });

    test('the bounding box contains the origin', () {
      expect(font.bounds.minX, lessThanOrEqualTo(0));
      expect(font.bounds.maxY, greaterThan(0));
    });

    test('an upright face has no italic angle', () {
      expect(font.italicAngle, 0);
    });

    test('a proportional face does not claim to be monospaced', () {
      expect(font.isFixedPitch, isFalse);
    });
  });

  group('character mapping', () {
    test('maps the letters it is asked for', () {
      expect(font.glyphFor('A'.codeUnitAt(0)), isNotNull);
      expect(font.glyphFor('z'.codeUnitAt(0)), isNotNull);
      expect(font.glyphFor(' '.codeUnitAt(0)), isNotNull);
    });

    test('different letters map to different glyphs', () {
      expect(
        font.glyphFor('A'.codeUnitAt(0)),
        isNot(font.glyphFor('B'.codeUnitAt(0))),
      );
    });

    // The rupee sign is the test that matters here: it is the character a
    // document written in India is most likely to carry that Latin-1 has no
    // room for. Liberation Sans, the first font tried, does not have it -
    // which is why this font is Noto.
    test('maps characters outside Latin-1', () {
      expect(font.glyphFor(0x20B9), isNotNull); // ₹
      expect(font.glyphFor(0x2014), isNotNull); // em dash
    });

    // Null, rather than glyph zero. Glyph zero draws a box, and a box on the
    // page looks like a font problem rather than a missing character.
    test('a character the font does not have has no glyph', () {
      expect(font.glyphFor(0x1F600), isNull); // an emoji
    });
  });

  group('widths', () {
    test('a wide letter measures wider than a narrow one', () {
      final w = font.advanceWidth(font.glyphFor('W'.codeUnitAt(0))!);
      final i = font.advanceWidth(font.glyphFor('i'.codeUnitAt(0))!);

      expect(w, greaterThan(i));
    });

    test('a space has a width', () {
      expect(
        font.advanceWidth(font.glyphFor(' '.codeUnitAt(0))!),
        greaterThan(0),
      );
    });

    // A capital letter is around three quarters of the em in any text face.
    // The point is that the scaling is applied at all: a width left in font
    // units is twice the size it should be on a 2048-unit grid.
    test('widths scale into the thousandths a PDF wants', () {
      final m = font.advanceWidth(font.glyphFor('M'.codeUnitAt(0))!);

      expect(m * 1000 / font.unitsPerEm, inInclusiveRange(600, 1000));
    });

    // Reading past the array is how a parser crashes on a font with a
    // monospaced tail.
    test('a glyph past the metric array still has a width', () {
      expect(font.advanceWidth(font.numGlyphs - 1), greaterThanOrEqualTo(0));
    });
  });

  group('outlines', () {
    test('a letter has an outline', () {
      final range = font.glyphRange(font.glyphFor('A'.codeUnitAt(0))!);

      expect(range.end, greaterThan(range.start));
    });

    test('a space has no outline', () {
      final range = font.glyphRange(font.glyphFor(' '.codeUnitAt(0))!);

      expect(range.end, range.start);
    });

    // An accented letter is a base and a mark referenced by index. A subset
    // that keeps the composite and drops its components draws nothing.
    test('a composite letter names the glyphs it is built from', () {
      final glyph = font.glyphFor(0xE9)!; // é
      final components = font.componentsOf(glyph);

      expect(components, isNotEmpty);
      expect(components, contains(font.glyphFor('e'.codeUnitAt(0))));
    });

    test('a simple letter is built from nothing else', () {
      expect(font.componentsOf(font.glyphFor('o'.codeUnitAt(0))!), isEmpty);
    });
  });
}

/// Where a table's four-letter tag sits in the table directory.
int _tagOffset(Uint8List bytes, String tag) {
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < data.getUint16(4); i++) {
    final at = 12 + i * 16;
    if (String.fromCharCodes(bytes.sublist(at, at + 4)) == tag) return at;
  }
  throw StateError('no $tag table');
}
