import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/fonts/pdf_embedded_font.dart';
import 'package:folio/domain/fonts/truetype_font.dart';
import 'package:folio/domain/fonts/truetype_subset.dart';

import 'synthetic_font.dart';

/// The paths the shipped font cannot reach. Noto is drawn on a 1000-unit grid
/// with long glyph offsets, a metric for every glyph and a character map with
/// no indirection - so four separate mutations survived every test built on
/// it, not because the code was right but because it was never run.
void main() {
  group('character map', () {
    // idRangeOffset is measured from the position of the ENTRY, not from the
    // start of the array. Every format 4 reader gets this wrong once.
    test('a segment that indirects through the glyph array is read', () {
      final font = TrueTypeFont.parse(syntheticFont());

      expect(font.glyphFor(0x42), 2); // B
      expect(font.glyphFor(0x43), 4); // C
    });

    test('a segment with a plain delta is read too', () {
      expect(TrueTypeFont.parse(syntheticFont()).glyphFor(0x41), 3);
    });

    // With the indirection turned off the same letters come through a delta,
    // so the two paths can be compared rather than taken on trust.
    test('both routes reach the same glyph', () {
      expect(
        TrueTypeFont.parse(
          syntheticFont(withRangeOffset: false),
        ).glyphFor(0x42),
        TrueTypeFont.parse(syntheticFont()).glyphFor(0x42),
      );
    });

    // Format 12 covers everything above the basic plane. Preferring format 4
    // when both exist silently loses every character above U+FFFF.
    test('format 12 wins over format 4', () {
      final font = TrueTypeFont.parse(syntheticFont(withFormat12: true));

      expect(font.glyphFor(0x41), 5);
    });
  });

  group('glyph offsets', () {
    // The short form stores half the offset. Reading it as written puts every
    // glyph at half its address, which lands inside the previous one.
    test('short offsets are doubled', () {
      final font = TrueTypeFont.parse(syntheticFont());
      final glyph = font.glyphRange(1);

      expect(font.indexToLocFormat, 0);
      expect(glyph.end, greaterThan(glyph.start));
      expect(glyph.end - glyph.start, greaterThan(8));
    });

    test('long offsets are read as they are', () {
      final font = TrueTypeFont.parse(syntheticFont(longLoca: true));
      final glyph = font.glyphRange(1);

      expect(font.indexToLocFormat, 1);
      expect(glyph.end - glyph.start, greaterThan(8));
    });

    test('both forms describe the same glyphs', () {
      final short = TrueTypeFont.parse(syntheticFont());
      final long = TrueTypeFont.parse(syntheticFont(longLoca: true));

      for (var glyph = 0; glyph < short.numGlyphs; glyph++) {
        expect(
          short.glyphRange(glyph).end - short.glyphRange(glyph).start,
          long.glyphRange(glyph).end - long.glyphRange(glyph).start,
          reason: 'glyph $glyph',
        );
      }
    });
  });

  group('widths', () {
    late TrueTypeFont font;

    setUp(() => font = TrueTypeFont.parse(syntheticFont()));

    test('a glyph inside the metric array has its own width', () {
      expect(font.advanceWidth(0), 100);
      expect(font.advanceWidth(4), 500);
    });

    // The tail of a font shares the last width. Reading past the array
    // returns whatever bytes follow it, which is a plausible-looking number.
    test('a glyph past the metric array shares the last width', () {
      expect(font.advanceWidth(5), font.advanceWidth(4));
      expect(font.advanceWidth(6), font.advanceWidth(4));
    });
  });

  group('composites', () {
    test('a composite names what it is built from', () {
      expect(TrueTypeFont.parse(syntheticFont()).componentsOf(3), contains(2));
    });

    // A composite may refer to another composite. Following only one level
    // keeps the letter and drops the mark it is made of.
    test('a composite of a composite is followed all the way down', () {
      final components = TrueTypeFont.parse(syntheticFont()).componentsOf(4);

      expect(components, containsAll([3, 2]));
    });

    test('a subset of a nested composite keeps every level', () {
      final font = TrueTypeFont.parse(syntheticFont());
      final subset = TrueTypeFont.parse(subsetFont(font, {4}));

      for (final glyph in [4, 3, 2]) {
        final range = subset.glyphRange(glyph);
        expect(range.end, greaterThan(range.start), reason: 'glyph $glyph');
      }
    });
  });

  group('the design grid', () {
    // PDF wants thousandths of the text size. A width left in font units is
    // twice as wide as it should be on a 2048-unit grid - and the shipped
    // font is drawn on a 1000-unit one, where the scaling is invisible.
    test('widths are scaled out of font units', () {
      final font = TrueTypeFont.parse(syntheticFont());
      final embedded = EmbeddedFont(font);

      expect(font.unitsPerEm, 2048);
      // 'A' is glyph 3, which is 400 units wide on a 2048-unit em.
      expect(embedded.encode('A').width, closeTo(400 * 1000 / 2048, 0.01));
    });

    test('the descriptor scales its metrics too', () {
      final font = TrueTypeFont.parse(syntheticFont());
      final embedded = EmbeddedFont(font)..encode('A');
      final descriptor = String.fromCharCodes(
        embedded.objects(1).firstWhere((o) => o.number == 3).body,
      );

      // The ascender is three quarters of a 2048 em, so 750 thousandths.
      expect(descriptor, contains('/Ascent 750'));
    });
  });

  group('subsetting a short-offset font', () {
    // A subset always writes long offsets, whatever the original used: the
    // short form cannot express an odd-sized glyf table at all.
    test('the subset declares long offsets', () {
      final font = TrueTypeFont.parse(syntheticFont());
      final subset = TrueTypeFont.parse(subsetFont(font, {1}));

      expect(font.indexToLocFormat, 0);
      expect(subset.indexToLocFormat, 1);
    });

    test('the kept glyph still has its outline', () {
      final font = TrueTypeFont.parse(syntheticFont());
      final subset = TrueTypeFont.parse(subsetFont(font, {1}));
      final range = subset.glyphRange(1);

      expect(range.end, greaterThan(range.start));
    });
  });
}
