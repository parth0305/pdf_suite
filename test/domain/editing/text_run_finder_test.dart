import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/text_run_finder.dart';

List<TextRun> runsOf(String source) => findTextRuns(latin1.encode(source));

TextRun runOf(String source) => runsOf(source).single;

void main() {
  group('matrices', () {
    test('the identity leaves a transform alone', () {
      const m = Matrix(2, 0, 0, 3, 10, 20);
      final result = m.then(Matrix.identity);

      expect([result.a, result.d, result.e, result.f], [2, 3, 10, 20]);
    });

    // Order matters, and is the thing everyone gets backwards.
    test('translation then scaling is not scaling then translation', () {
      const translate = Matrix(1, 0, 0, 1, 10, 0);
      const scale = Matrix(2, 0, 0, 2, 0, 0);

      expect(translate.then(scale).e, 20);
      expect(scale.then(translate).e, 10);
    });

    // All six elements, against values worked out by hand. Every other test
    // here uses upright text, where b and c are both zero and two of the six
    // products cancel - so a multiply with its rows and columns swapped gives
    // the right answer for all of them.
    test('multiplies every element, not only the ones text usually uses', () {
      const first = Matrix(1, 2, 3, 4, 5, 6);
      const second = Matrix(7, 8, 9, 10, 11, 12);
      final result = first.then(second);

      expect(
        [result.a, result.b, result.c, result.d, result.e, result.f],
        [25, 28, 57, 64, 100, 112],
      );
    });

    test('a scale is reported as one', () {
      expect(const Matrix(3, 0, 0, 4, 0, 0).verticalScale, closeTo(4, 0.0001));
    });

    // A quarter turn puts the scale in b and c, so a reader that only looks
    // at d thinks the text has no size at all.
    test('a rotated transform still has a scale', () {
      expect(
        const Matrix(0, 12, -12, 0, 0, 0).verticalScale,
        closeTo(12, 0.0001),
      );
    });
  });

  group('finding runs', () {
    test('a shown string is a run', () {
      final run = runOf('BT /F1 12 Tf 72 700 Td (Hello) Tj ET');

      expect(rawTextOf(run), 'Hello');
      expect(run.fontName, 'F1');
      expect(run.fontSize, 12);
    });

    test('several strings are several runs', () {
      final runs = runsOf('BT /F1 12 Tf (One) Tj 0 -14 Td (Two) Tj ET');

      expect(runs.map(rawTextOf), ['One', 'Two']);
    });

    // The numbers between them are kerning. An edit replaces one string
    // without disturbing the shifts around it.
    test('each string in a TJ array is its own run', () {
      final runs = runsOf('BT /F1 12 Tf [(A) -120 (B) 35 (C)] TJ ET');

      expect(runs.map(rawTextOf), ['A', 'B', 'C']);
      expect(runs.every((r) => r.source == TextRunSource.showAdjusted), isTrue);
    });

    test('a hex string is a run of the bytes it stands for', () {
      final run = runOf('BT /F1 12 Tf <48656C6C6F> Tj ET');

      expect(rawTextOf(run), 'Hello');
    });

    // <4> is the byte 0x40, not 0x04: an odd digit count is padded at the
    // END. Padding at the front reads every such string wrong.
    test('an odd hex string is padded with a trailing zero', () {
      expect(runOf('BT /F1 12 Tf <4> Tj ET').bytes, [0x40]);
    });

    test('a page with no text has no runs', () {
      expect(runsOf('q 1 0 0 1 0 0 cm 0 0 100 100 re f Q'), isEmpty);
    });

    test('an inline image is not a run', () {
      expect(runsOf('q BI /W 1 /H 1 ID (x) Tj EI Q'), isEmpty);
    });
  });

  group('what the bytes are', () {
    // The escapes are how the bytes were written down, not the bytes. An edit
    // that measured the written form would count the backslashes.
    test('an escaped bracket is one byte', () {
      expect(rawTextOf(runOf(r'BT (a \( b) Tj ET')), 'a ( b');
    });

    test('an escaped backslash is one byte', () {
      expect(rawTextOf(runOf(r'BT (a \\ b) Tj ET')), r'a \ b');
    });

    test('an octal escape is the byte it names', () {
      expect(runOf(r'BT (\101\102) Tj ET').bytes, [65, 66]);
    });

    test('a short octal escape still ends at the next character', () {
      expect(runOf(r'BT (\7A) Tj ET').bytes, [7, 0x41]);
    });

    test('the named escapes are their characters', () {
      expect(runOf(r'BT (\n\r\t\b\f) Tj ET').bytes, [10, 13, 9, 8, 12]);
    });

    // A backslash at the end of a line continues the string and adds nothing.
    test('a line continuation adds nothing', () {
      expect(rawTextOf(runOf('BT (one\\\ntwo) Tj ET')), 'onetwo');
    });

    test('an unknown escape is the character itself', () {
      expect(rawTextOf(runOf(r'BT (\q) Tj ET')), 'q');
    });

    test('nested brackets are kept', () {
      expect(rawTextOf(runOf('BT ((inner)) Tj ET')), '(inner)');
    });
  });

  group('where a run is', () {
    test('Td moves the text', () {
      final run = runOf('BT /F1 12 Tf 72 700 Td (Hi) Tj ET');

      expect(run.position.x, 72);
      expect(run.position.y, 700);
    });

    test('Td is relative to the line before it', () {
      final runs = runsOf(
        'BT /F1 12 Tf 72 700 Td (One) Tj 10 -14 Td (Two) Tj ET',
      );

      expect(runs.last.position.x, 82);
      expect(runs.last.position.y, 686);
    });

    test('Tm replaces the text matrix rather than adding to it', () {
      final runs = runsOf(
        'BT /F1 12 Tf 72 700 Td (One) Tj 1 0 0 1 100 500 Tm (Two) Tj ET',
      );

      expect(runs.last.position.x, 100);
      expect(runs.last.position.y, 500);
    });

    // BT resets the text matrix. Carrying it across text objects puts the
    // second one wherever the first one finished.
    test('BT starts again from the origin', () {
      final runs = runsOf('BT /F1 12 Tf 72 700 Td (One) Tj ET BT (Two) Tj ET');

      expect(runs.last.position.x, 0);
      expect(runs.last.position.y, 0);
    });

    test('the graphics state moves the text too', () {
      final run = runOf(
        'q 1 0 0 1 50 50 cm BT /F1 12 Tf 10 10 Td (Hi) Tj ET Q',
      );

      expect(run.position.x, 60);
      expect(run.position.y, 60);
    });

    // Q restores what q saved. Without that, everything after a restored
    // block is drawn in the block's coordinates.
    test('the state is restored after Q', () {
      final runs = runsOf('q 1 0 0 1 50 50 cm BT (In) Tj ET Q BT (Out) Tj ET');

      expect(runs.first.position.x, 50);
      expect(runs.last.position.x, 0);
    });

    test('an unbalanced Q does not stop the rest of the page', () {
      final runs = runsOf('Q BT /F1 12 Tf 10 20 Td (Hi) Tj ET');

      expect(runs.single.position.x, 10);
    });

    test('T* moves down by the leading', () {
      final runs = runsOf(
        'BT /F1 12 Tf 14 TL 72 700 Td (One) Tj T* (Two) Tj ET',
      );

      expect(runs.last.position.y, 686);
    });

    // TD sets the leading as a side effect, to MINUS its second operand - so
    // moving DOWN by 14 sets a leading of 14, and the T* after it moves down
    // by the same amount without being told to.
    test('TD sets the leading as well as moving', () {
      final runs = runsOf(
        'BT /F1 12 Tf 72 700 Td 0 -14 TD (One) Tj T* (Two) Tj ET',
      );

      expect(runs.first.position.y, 686);
      expect(runs.last.position.y, 672);
    });

    // Without the sign flip the leading is 14 the wrong way and every line
    // after the first climbs the page.
    test('TD does not move the next line upwards', () {
      final runs = runsOf('BT /F1 12 Tf 0 -14 TD (One) Tj T* (Two) Tj ET');

      expect(runs.last.position.y, lessThan(runs.first.position.y));
    });

    test("the quote operator moves to the next line first", () {
      final runs = runsOf("BT /F1 12 Tf 16 TL 72 700 Td (One) Tj (Two) ' ET");

      expect(runs.last.position.y, 684);
      expect(runs.last.source, TextRunSource.nextLineShow);
    });

    test('the double quote operator does too', () {
      final runs = runsOf(
        'BT /F1 12 Tf 16 TL 72 700 Td (One) Tj 1 2 (Two) " ET',
      );

      expect(runs.last.position.y, 684);
      expect(rawTextOf(runs.last), 'Two');
    });

    test('the size scales the transform', () {
      final run = runOf('BT /F1 24 Tf 0 0 Td (Hi) Tj ET');

      expect(run.transform.verticalScale, closeTo(24, 0.0001));
    });

    test('a scaled graphics state scales the text with it', () {
      final run = runOf('q 2 0 0 2 0 0 cm BT /F1 12 Tf (Hi) Tj ET Q');

      expect(run.transform.verticalScale, closeTo(24, 0.0001));
    });

    test('a rise lifts the text off the baseline', () {
      final run = runOf('BT /F1 12 Tf 72 700 Td 5 Ts (Hi) Tj ET');

      expect(run.position.y, 705);
    });
  });

  group('what can be edited', () {
    // Mode 3 is invisible text: OCR puts it under a scan, and editing it
    // changes nothing anybody can see.
    test('invisible text is marked invisible', () {
      final run = runOf('BT /F1 12 Tf 3 Tr (hidden) Tj ET');

      expect(run.isVisible, isFalse);
    });

    test('ordinary text is visible', () {
      expect(runOf('BT /F1 12 Tf (shown) Tj ET').isVisible, isTrue);
    });

    test('a stroked and clipped mode is invisible too', () {
      expect(runOf('BT /F1 12 Tf 7 Tr (clip) Tj ET').isVisible, isFalse);
    });

    test('text shown without a font has no font name', () {
      expect(runOf('BT (orphan) Tj ET').fontName, isNull);
    });
  });

  group('spans', () {
    // The string's own span, so an edit replaces the text and nothing else -
    // which matters when one operator carries several strings.
    test('a run points at its own string', () {
      final source = 'BT /F1 12 Tf [(A) -120 (B)] TJ ET';
      final runs = runsOf(source);

      expect(
        source.substring(runs.first.stringStart, runs.first.stringEnd),
        '(A)',
      );
      expect(
        source.substring(runs.last.stringStart, runs.last.stringEnd),
        '(B)',
      );
    });

    test('a run also points at the whole operation', () {
      const source = 'BT /F1 12 Tf [(A) -120 (B)] TJ ET';
      final run = runsOf(source).first;

      expect(
        source.substring(run.operationStart, run.operationEnd),
        '[(A) -120 (B)] TJ',
      );
    });

    test('the span of a simple show covers its string and operator', () {
      const source = 'BT (Hi) Tj ET';
      final run = runsOf(source).single;

      expect(source.substring(run.operationStart, run.operationEnd), '(Hi) Tj');
    });
  });
}
