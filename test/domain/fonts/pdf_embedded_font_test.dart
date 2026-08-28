import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/fonts/pdf_embedded_font.dart';
import 'package:folio/domain/fonts/truetype_font.dart';

void main() {
  late TrueTypeFont noto;

  setUpAll(
    () => noto = TrueTypeFont.parse(
      File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync(),
    ),
  );

  EmbeddedFont fresh() => EmbeddedFont(noto);

  String bodyOf(List<FontObject> objects, int number) => latin1.decode(
    objects.firstWhere((o) => o.number == number).body,
    allowInvalid: true,
  );

  group('encoding', () {
    test('gives two bytes per character', () {
      expect(fresh().encode('Hi').hex.length, 8);
    });

    test('the same letter encodes the same way twice', () {
      final font = fresh();

      expect(font.encode('A').hex, font.encode('A').hex);
    });

    test('different letters encode differently', () {
      final font = fresh();

      expect(font.encode('A').hex, isNot(font.encode('B').hex));
    });

    test('a wider letter measures wider', () {
      final font = fresh();

      expect(font.encode('W').width, greaterThan(font.encode('i').width));
    });

    // Thousandths of the text size, which is what a PDF text operator wants.
    // A width left in font units is twice as wide on a 2048-unit grid.
    test('widths are in thousandths of the text size', () {
      expect(fresh().encode('M').width, inInclusiveRange(500, 1000));
    });

    test('a longer string measures longer', () {
      final font = fresh();

      expect(
        font.encode('Hello there').width,
        greaterThan(font.encode('Hello').width),
      );
    });

    // The character this app cannot do without.
    test('the rupee sign encodes', () {
      final encoded = fresh().encode('₹48,500');

      expect(encoded.missing, isEmpty);
      expect(encoded.hex.length, 28);
    });

    // Reported, not replaced. Glyph zero draws a box, and a row of boxes
    // looks like a broken document rather than a missing character.
    test('a character the font lacks is reported', () {
      final encoded = fresh().encode('a\u{1F600}b');

      expect(encoded.missing, [0x1F600]);
      expect(encoded.hex.length, 8);
    });

    test('measuring does not add the glyphs to the subset', () {
      final font = fresh()..measure('Hello');

      expect(font.isEmpty, isTrue);
    });
  });

  group('the objects', () {
    late List<FontObject> objects;

    setUp(() {
      final font = fresh()..encode('Hello');
      objects = font.objects(10);
    });

    test('there are as many as the caller was told to reserve', () {
      expect(objects.length, EmbeddedFont.objectCount);
      expect(objects.map((o) => o.number), [10, 11, 12, 13, 14]);
    });

    // The first is the one a page's resources point at.
    test('the first is the font itself', () {
      expect(bodyOf(objects, 10), contains('/Subtype /Type0'));
      expect(bodyOf(objects, 10), contains('/Encoding /Identity-H'));
    });

    test('the font names its descendant, descriptor and file', () {
      expect(bodyOf(objects, 10), contains('/DescendantFonts [11 0 R]'));
      expect(bodyOf(objects, 11), contains('/FontDescriptor 12 0 R'));
      expect(bodyOf(objects, 12), contains('/FontFile2 13 0 R'));
      expect(bodyOf(objects, 10), contains('/ToUnicode 14 0 R'));
    });

    test('the descendant maps glyph identifiers straight through', () {
      expect(bodyOf(objects, 11), contains('/CIDToGIDMap /Identity'));
    });

    test('the descriptor carries the metrics a reader needs', () {
      final descriptor = bodyOf(objects, 12);

      expect(descriptor, contains('/Ascent'));
      expect(descriptor, contains('/Descent'));
      expect(descriptor, contains('/FontBBox'));
      expect(descriptor, contains('/CapHeight'));
    });

    test('the file carries its uncompressed length', () {
      expect(bodyOf(objects, 13), contains('/Length1'));
    });

    // A subset tag, so two subsets of one font are not taken for each other.
    test('the name carries a subset tag', () {
      expect(
        RegExp(
          r'/BaseFont /([A-Z]{6})\+NotoSans',
        ).hasMatch(bodyOf(objects, 10)),
        isTrue,
      );
    });

    test('the same text gives the same tag, and different text does not', () {
      String tagFor(String text) => RegExp(
        r'/BaseFont /([A-Z]{6})\+',
      ).firstMatch(bodyOf((fresh()..encode(text)).objects(10), 10))!.group(1)!;

      expect(tagFor('Hello'), tagFor('Hello'));
      expect(tagFor('Hello'), isNot(tagFor('Different letters entirely')));
    });

    test('widths are declared for the glyphs used', () {
      expect(bodyOf(objects, 11), contains('/W ['));
      expect(bodyOf(objects, 11), isNot(contains('/W []')));
    });

    // Without this a reader can draw the text and nothing else: no selecting,
    // no copying, no searching, no extraction.
    test('a map back to characters is carried', () {
      final map = latin1.decode(
        ZLibCodec().decode(
          objects
              .firstWhere((o) => o.number == 14)
              .body
              .sublist(
                latin1
                        .decode(
                          objects.firstWhere((o) => o.number == 14).body,
                          allowInvalid: true,
                        )
                        .indexOf('stream\n') +
                    7,
              ),
        ),
        allowInvalid: true,
      );

      expect(map, contains('beginbfchar'));
      expect(map, contains('/CMapType 2 def'));
      // 'H' is U+0048.
      expect(map, contains('<0048>'));
    });

    test('the embedded font is a fraction of the whole one', () {
      final file = objects.firstWhere((o) => o.number == 13).body;

      expect(file.length, lessThan(noto.bytes.length ~/ 10));
    });
  });
}
