import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/font_encoding.dart';

/// The CMap Folio writes into every font it embeds, in miniature.
String cmapOf(String body, {String codespace = '<0000> <FFFF>'}) =>
    '/CIDInit /ProcSet findresource begin\n'
    'begincmap\n'
    '1 begincodespacerange\n'
    '$codespace\n'
    'endcodespacerange\n'
    '$body\n'
    'endcmap\n'
    'end';

void main() {
  group('a font that says what its bytes mean', () {
    test('reads a character at a time', () {
      final decoder = parseToUnicodeCMap(
        cmapOf('2 beginbfchar\n<0024> <0041>\n<0025> <0042>\nendbfchar'),
      )!;

      expect(decoder.decode([0x00, 0x24, 0x00, 0x25]), 'AB');
    });

    test('reads a range', () {
      final decoder = parseToUnicodeCMap(
        cmapOf('1 beginbfrange\n<0030> <0039> <0030>\nendbfrange'),
      )!;

      expect(decoder.decode([0x00, 0x33]), '3');
      expect(decoder.decode([0x00, 0x39]), '9');
    });

    // A range whose destination is a list gives one value per code. Reading
    // it as the plain form maps the whole range to the first entry.
    test('reads a range with a destination for each code', () {
      final decoder = parseToUnicodeCMap(
        cmapOf(
          '1 beginbfrange\n<0010> <0012> [<0041> <0043> <0045>]\nendbfrange',
        ),
      )!;

      expect(decoder.decode([0x00, 0x10]), 'A');
      expect(decoder.decode([0x00, 0x11]), 'C');
      expect(decoder.decode([0x00, 0x12]), 'E');
    });

    // Two bytes per code for the identity encodings. Reading such a font one
    // byte at a time gives twice as many characters, all of them wrong.
    test('the codespace decides how many bytes make a code', () {
      final two = parseToUnicodeCMap(
        cmapOf('1 beginbfchar\n<0041> <0041>\nendbfchar'),
      )!;
      final one = parseToUnicodeCMap(
        cmapOf('1 beginbfchar\n<41> <0041>\nendbfchar', codespace: '<00> <FF>'),
      )!;

      expect(two.codeLength, 2);
      expect(one.codeLength, 1);
      expect(one.decode([0x41]), 'A');
    });

    test('a code the map does not cover cannot be read', () {
      final decoder = parseToUnicodeCMap(
        cmapOf('1 beginbfchar\n<0024> <0041>\nendbfchar'),
      )!;

      expect(decoder.decode([0x00, 0x99]), isNull);
    });

    // All or nothing: a partly-read run looks editable and re-encodes wrongly.
    test('one unreadable code makes the whole run unreadable', () {
      final decoder = parseToUnicodeCMap(
        cmapOf('1 beginbfchar\n<0024> <0041>\nendbfchar'),
      )!;

      expect(decoder.decode([0x00, 0x24, 0x00, 0x99]), isNull);
    });

    test('bytes that do not divide into codes cannot be read', () {
      final decoder = parseToUnicodeCMap(
        cmapOf('1 beginbfchar\n<0024> <0041>\nendbfchar'),
      )!;

      expect(decoder.decode([0x00]), isNull);
    });

    // Anything above the basic plane arrives as a surrogate pair.
    test('reads a character above the basic plane', () {
      final decoder = parseToUnicodeCMap(
        cmapOf('1 beginbfchar\n<0001> <D83DDE00>\nendbfchar'),
      )!;

      expect(decoder.decode([0x00, 0x01]), '\u{1F600}');
    });

    test('a map with nothing in it is no map at all', () {
      expect(parseToUnicodeCMap(cmapOf('')), isNull);
    });

    // A damaged CMap should fail, not exhaust memory.
    test('an absurd range is skipped rather than expanded', () {
      final decoder = parseToUnicodeCMap(
        cmapOf(
          '2 beginbfrange\n<0000> <FFFFFF> <0041>\n<0030> <0031> <0030>\n'
          'endbfrange',
        ),
      );

      expect(decoder, isNotNull);
      expect(decoder!.decode([0x00, 0x30]), '0');
      // And the codes the absurd range would have covered are not mapped:
      // expanding it fills sixteen million entries to answer a question
      // nobody asked.
      expect(decoder.decode([0xFF, 0xFF]), isNull);
    });

    test('the rupee sign survives a round trip through a map', () {
      final decoder = parseToUnicodeCMap(
        cmapOf('1 beginbfchar\n<0005> <20B9>\nendbfchar'),
      )!;

      expect(decoder.decode([0x00, 0x05]), '₹');
    });
  });

  group('a font with a standard encoding', () {
    test('reads the printable range', () {
      final decoder = simpleFontDecoder(baseEncoding: 'WinAnsiEncoding');

      expect(decoder.decode([0x48, 0x65, 0x6C, 0x6C, 0x6F]), 'Hello');
    });

    // WinAnsi and Latin-1 agree everywhere except 0x80 to 0x9F, where Latin-1
    // has control characters and WinAnsi has punctuation. Reading one as the
    // other turns every curly quote into a control character.
    test('WinAnsi has punctuation where Latin-1 has control characters', () {
      final decoder = simpleFontDecoder(baseEncoding: 'WinAnsiEncoding');

      expect(decoder.decode([0x92]), '’');
      expect(decoder.decode([0x93]), '“');
      expect(decoder.decode([0x80]), '€');
    });

    test('WinAnsi reads the accented letters as Latin-1 does', () {
      expect(
        simpleFontDecoder(baseEncoding: 'WinAnsiEncoding').decode([0xE9]),
        'é',
      );
    });

    // MacRoman shares nothing with Latin-1 above 0x7F.
    test('MacRoman is not Latin-1', () {
      final decoder = simpleFontDecoder(baseEncoding: 'MacRomanEncoding');

      expect(decoder.decode([0x8E]), 'é');
      expect(decoder.decode([0xA5]), '•');
    });

    // StandardEncoding is not implemented above ASCII, and says so rather
    // than guessing.
    test('an unstated encoding reads ASCII and refuses the rest', () {
      final decoder = simpleFontDecoder();

      expect(decoder.decode([0x41]), 'A');
      expect(decoder.decode([0xE9]), isNull);
    });
  });

  group('a font with exceptions', () {
    // The whole point of /Differences: this document says byte 65 is not A.
    test('a difference overrides the base encoding', () {
      final decoder = simpleFontDecoder(
        baseEncoding: 'WinAnsiEncoding',
        differences: '[65 /bullet]',
      );

      expect(decoder.decode([65]), '•');
      expect(decoder.decode([66]), 'B');
    });

    // Names run on from the last number given, so one number can rename a
    // whole run of codes.
    test('names after a number number themselves', () {
      final decoder = simpleFontDecoder(
        baseEncoding: 'WinAnsiEncoding',
        differences: '[65 /one /two /three]',
      );

      expect(decoder.decode([65, 66, 67]), '123');
    });

    test('a second number starts again from there', () {
      final decoder = simpleFontDecoder(
        baseEncoding: 'WinAnsiEncoding',
        differences: '[65 /one 200 /two]',
      );

      expect(decoder.decode([65]), '1');
      expect(decoder.decode([200]), '2');
    });

    test('a name that states its own code point is read', () {
      final decoder = simpleFontDecoder(differences: '[1 /uni20B9 2 /u00E9]');

      expect(decoder.decode([1]), '₹');
      expect(decoder.decode([2]), 'é');
    });

    // A name nobody knows is unreadable, not a guess - and it must also
    // REMOVE what the base encoding said, or the exception is ignored.
    test('an unknown name makes that byte unreadable', () {
      final decoder = simpleFontDecoder(
        baseEncoding: 'WinAnsiEncoding',
        differences: '[65 /gXYZ]',
      );

      expect(decoder.decode([65]), isNull);
      expect(decoder.decode([66]), 'B');
    });

    test('a font with only differences still reads them', () {
      expect(simpleFontDecoder(differences: '[7 /space]').decode([7]), ' ');
    });
  });

  group('glyph names', () {
    test('the ones a differences array actually uses', () {
      expect(glyphNameToCharacter('space'), ' ');
      expect(glyphNameToCharacter('eacute'), 'é');
      expect(glyphNameToCharacter('quoteright'), '’');
      expect(glyphNameToCharacter('Euro'), '€');
      expect(glyphNameToCharacter('fi'), 'ﬁ');
    });

    test('the forms that state their own code point', () {
      expect(glyphNameToCharacter('uni0041'), 'A');
      expect(glyphNameToCharacter('u20B9'), '₹');
    });

    test('a name nobody knows has no character', () {
      expect(glyphNameToCharacter('glyph00123'), isNull);
      expect(glyphNameToCharacter('uniZZZZ'), isNull);
    });
  });
}
