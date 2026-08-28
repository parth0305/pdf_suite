import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/font_encoding.dart';
import 'package:folio/domain/editing/text_edit.dart';
import 'package:folio/domain/editing/text_run_finder.dart';

/// A font that can write ASCII and knows every glyph is 500 thousandths wide,
/// so a width difference is exactly the difference in length.
FontDecoder get evenFont => simpleFontDecoder(baseEncoding: 'WinAnsiEncoding');

double? evenWidths(int code) => 500;

TextRun runIn(String source, {int index = 0}) =>
    findTextRuns(latin1.encode(source))[index];

EditPlan planIn(
  String source,
  String replacement, {
  int index = 0,
  FontDecoder? decoder,
  double? Function(int code)? widths,
  double? availableWidth,
}) => planTextEdit(
  run: runIn(source, index: index),
  replacement: replacement,
  decoder: decoder ?? evenFont,
  widthOf: widths ?? evenWidths,
  availableWidth: availableWidth,
);

String applyIn(String source, String replacement, {int index = 0}) {
  final stream = latin1.encode(source);
  final run = findTextRuns(stream)[index];
  final plan = planTextEdit(
    run: run,
    replacement: replacement,
    decoder: evenFont,
    widthOf: evenWidths,
  );

  return latin1.decode(applyTextEdit(stream, run, plan as EditPatch));
}

void main() {
  group('planning', () {
    test('a replacement of the same length needs no adjustment', () {
      final plan = planIn('BT /F1 12 Tf (48500) Tj ET', '52000');

      expect(plan, isA<EditPatch>());
      expect((plan as EditPatch).adjustment, 0);
      expect(latin1.decode(plan.replacement), '52000');
    });

    // A positive number in a TJ array SUBTRACTS from the advance, so making
    // the text NARROWER needs a negative one. The sign catches everyone.
    test('a shorter replacement widens the gap after it', () {
      final plan = planIn('BT /F1 12 Tf (48500) Tj ET', '500') as EditPatch;

      // Two glyphs fewer, 500 thousandths each.
      expect(plan.adjustment, -1000);
    });

    test('a longer replacement narrows the gap after it', () {
      final plan = planIn('BT /F1 12 Tf (500) Tj ET', '48500') as EditPatch;

      expect(plan.adjustment, 1000);
    });

    test('the patch covers the string and nothing else', () {
      const source = 'BT /F1 12 Tf (48500) Tj ET';
      final plan = planIn(source, '1') as EditPatch;

      expect(source.substring(plan.start, plan.end), '(48500)');
    });
  });

  group('refusing', () {
    // A font subsetted for one phrase has no other letters in it. Writing
    // them anyway draws nothing, and nothing reports it.
    test('a character the font cannot write', () {
      final plan = planIn('BT /F1 12 Tf (abc) Tj ET', 'ab₹');

      expect(plan, isA<EditRefused>());
      expect((plan as EditRefused).reason, EditRefusal.missingCharacters);
      expect(plan.detail, ['₹']);
    });

    test('every character it cannot write is named', () {
      final plan =
          planIn('BT /F1 12 Tf (abc) Tj ET', '₹ and नमस') as EditRefused;

      expect(plan.detail, contains('₹'));
      expect(plan.detail.length, greaterThan(1));
    });

    test('a run whose own bytes cannot be read', () {
      final plan = planIn(
        'BT /F1 12 Tf <FF> Tj ET',
        'new',
        decoder: simpleFontDecoder(),
      );

      expect((plan as EditRefused).reason, EditRefusal.unreadable);
    });

    // OCR puts invisible text under a scan. Editing it changes nothing
    // anybody can see, which is not what the person asking expected.
    test('invisible text', () {
      final plan = planIn('BT /F1 12 Tf 3 Tr (hidden) Tj ET', 'shown');

      expect((plan as EditRefused).reason, EditRefusal.notVisible);
    });

    // A guessed width shifts everything after the edit by however wrong the
    // guess was, and nothing reports that either.
    test('a font whose widths are not known', () {
      final plan = planIn(
        'BT /F1 12 Tf (abc) Tj ET',
        'xyz',
        widths: (code) => null,
      );

      expect((plan as EditRefused).reason, EditRefusal.unknownWidths);
    });

    test('a replacement that would run into what follows', () {
      final plan = planIn(
        'BT /F1 12 Tf (a) Tj ET',
        'a much longer replacement',
        availableWidth: 10,
      );

      expect((plan as EditRefused).reason, EditRefusal.wouldOverlap);
      expect(plan.detail.single, contains('points'));
    });

    test('a replacement that fits in the space is allowed', () {
      final plan = planIn('BT /F1 12 Tf (a) Tj ET', 'ab', availableWidth: 10);

      expect(plan, isA<EditPatch>());
    });

    // Widths are in thousandths of the text size, and the gap is in points.
    // Comparing them without multiplying by the size understates the overrun
    // by a factor of the font size - here, twelvefold - and lets an edit
    // through that runs a whole word into the next one.
    test('the overrun is measured at the size the text is set in', () {
      final plan = planIn('BT /F1 12 Tf (a) Tj ET', 'abc', availableWidth: 5);

      expect((plan as EditRefused).reason, EditRefusal.wouldOverlap);
    });

    // Without a width to check against, an overlap cannot be ruled out - and
    // the caller is trusted rather than the edit being blocked.
    test('an unknown available width does not refuse', () {
      final plan = planIn('BT /F1 12 Tf (a) Tj ET', 'a much longer one');

      expect(plan, isA<EditPatch>());
    });
  });

  group('applying', () {
    test('a simple show keeps its operator when nothing shifts', () {
      expect(
        applyIn('BT /F1 12 Tf (48500) Tj ET', '52000'),
        'BT /F1 12 Tf (52000) Tj ET',
      );
    });

    // Only TJ can carry the number that keeps the rest of the line put, so a
    // Tj that needs one becomes a TJ.
    test('a show that shifts becomes an array', () {
      expect(
        applyIn('BT /F1 12 Tf (48500) Tj ET', '500'),
        'BT /F1 12 Tf [(500) -1000 ] TJ ET',
      );
    });

    // Everything else in the array - every other string, every kerning
    // number - is left exactly as it was.
    test('one string in an array is replaced and the rest left alone', () {
      expect(
        applyIn('BT /F1 12 Tf [(A) -120 (BB) 35 (C)] TJ ET', 'DD', index: 1),
        'BT /F1 12 Tf [(A) -120 (DD) 35 (C)] TJ ET',
      );
    });

    test('an array entry that shifts gets its own adjustment', () {
      expect(
        applyIn('BT /F1 12 Tf [(A) -120 (BB) 35 (C)] TJ ET', 'D', index: 1),
        'BT /F1 12 Tf [(A) -120 (D) -500  35 (C)] TJ ET',
      );
    });

    // A bracket in the replacement would end the string early and turn the
    // rest of the page into operators.
    test('a bracket in the replacement is escaped', () {
      expect(
        applyIn('BT /F1 12 Tf (ab) Tj ET', '()'),
        r'BT /F1 12 Tf (\(\)) Tj ET',
      );
    });

    // Three characters replacing three, so the operator stays a Tj and the
    // escaping is the only thing this test is looking at.
    test('a backslash in the replacement is escaped', () {
      expect(
        applyIn('BT /F1 12 Tf (abc) Tj ET', r'a\b'),
        r'BT /F1 12 Tf (a\\b) Tj ET',
      );
    });

    test('everything outside the operation is untouched', () {
      final out = applyIn(
        'q 1 0 0 1 5 5 cm BT /F1 12 Tf (old) Tj ET Q 0 0 10 10 re f',
        'new',
      );

      expect(out, startsWith('q 1 0 0 1 5 5 cm BT'));
      expect(out, endsWith('ET Q 0 0 10 10 re f'));
    });

    // `'` moves to the next line and then shows. An array cannot do that, so
    // the move has to be written out separately or the line is drawn on top
    // of the one before it.
    test('a quote operator keeps its line break when it becomes an array', () {
      final out = applyIn("BT /F1 12 Tf 14 TL (old) ' ET", 'a');

      expect(out, contains('T* ['));
      expect(out, contains('TJ'));
    });

    test('a quote operator that does not shift stays a quote', () {
      expect(
        applyIn("BT /F1 12 Tf 14 TL (old) ' ET", 'new'),
        "BT /F1 12 Tf 14 TL (new) ' ET",
      );
    });
  });

  group('a font that says what its bytes mean', () {
    ToUnicodeDecoder mapped() => parseToUnicodeCMap(
      'begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n'
      '3 beginbfchar\n<0001> <0041>\n<0002> <0042>\n<0003> <20B9>\n'
      'endbfchar',
    )!;

    test('text is written back as the codes that font uses', () {
      final stream = latin1.encode('BT /F1 12 Tf <00010002> Tj ET');
      final run = findTextRuns(stream).single;

      final plan = planTextEdit(
        run: run,
        replacement: 'BA',
        decoder: mapped(),
        widthOf: evenWidths,
      );

      expect((plan as EditPatch).replacement, [0x00, 0x02, 0x00, 0x01]);
    });

    // The character this app cannot do without, and the case that proves the
    // encoding is the font's own rather than Latin-1.
    test('the rupee sign is written as the code the font gave it', () {
      final stream = latin1.encode('BT /F1 12 Tf <0001> Tj ET');
      final run = findTextRuns(stream).single;

      final plan = planTextEdit(
        run: run,
        replacement: '₹',
        decoder: mapped(),
        widthOf: evenWidths,
      );

      expect((plan as EditPatch).replacement, [0x00, 0x03]);
    });

    test('a character the map has no code for is refused', () {
      final stream = latin1.encode('BT /F1 12 Tf <0001> Tj ET');
      final run = findTextRuns(stream).single;

      final plan = planTextEdit(
        run: run,
        replacement: 'Z',
        decoder: mapped(),
        widthOf: evenWidths,
      );

      expect((plan as EditRefused).reason, EditRefusal.missingCharacters);
    });

    // Two bytes to a code. Measuring one byte at a time counts twice as many
    // glyphs and compensates by twice as much.
    test('widths are counted per code, not per byte', () {
      final stream = latin1.encode('BT /F1 12 Tf <00010002> Tj ET');
      final run = findTextRuns(stream).single;

      final plan = planTextEdit(
        run: run,
        replacement: 'A',
        decoder: mapped(),
        widthOf: evenWidths,
      );

      // One glyph instead of two: 500 thousandths narrower.
      expect((plan as EditPatch).adjustment, -500);
    });
  });

  group('writing back', () {
    test('a ligature is written as the one code that draws it', () {
      final decoder = simpleFontDecoder(differences: '[1 /fi]');

      expect(decoder.encode('ﬁ'), [1]);
    });

    // Where two codes give the same character the lower one wins, so the same
    // edit always writes the same bytes.
    test('a duplicated character encodes the same way every time', () {
      final decoder = simpleFontDecoder(differences: '[10 /space 20 /space]');

      expect(decoder.encode(' '), [10]);
      expect(decoder.encode(' '), [10]);
    });

    // One code standing for two characters. Encoding a character at a time
    // never finds it, and the pair is reported as unwritable even though the
    // font has a glyph for exactly that.
    test('a code standing for two characters is written as that code', () {
      final decoder = parseToUnicodeCMap(
        'begincodespacerange\n<00> <FF>\nendcodespacerange\n'
        '2 beginbfchar\n<01> <00660069>\n<02> <0061>\nendbfchar',
      )!;

      expect(decoder.decode([0x01]), 'fi');
      expect(decoder.encode('fi'), [0x01]);
      expect(decoder.encode('afi'), [0x02, 0x01]);
    });

    // encode() is used on its own, not only behind the check that runs first
    // in planning - so it has to refuse by itself.
    test('a string it cannot fully write encodes to nothing', () {
      final decoder = simpleFontDecoder(baseEncoding: 'WinAnsiEncoding');

      expect(decoder.encode('a₹b'), isNull);
      expect(decoder.encode('ab'), isNotNull);
    });

    test('what it cannot write, it names', () {
      expect(
        simpleFontDecoder(baseEncoding: 'WinAnsiEncoding').missingFrom('a₹b'),
        ['₹'],
      );
    });

    test('what it can write, it does not complain about', () {
      expect(
        simpleFontDecoder(baseEncoding: 'WinAnsiEncoding').missingFrom('abc'),
        isEmpty,
      );
    });
  });
}
