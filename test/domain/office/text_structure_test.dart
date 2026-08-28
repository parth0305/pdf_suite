import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/office/text_structure.dart';

/// Builds a page of text where every character is placed on a grid: [left] is
/// the first character's left edge, each character is [width] wide, and each
/// line sits [leading] below the one before.
///
/// Lines are given as (text, left, baseline) so a test can put them wherever
/// the case needs.
PageText page(
  List<({String text, double left, double baseline})> lines, {
  double width = 6,
  double height = 10,
}) {
  final buffer = StringBuffer();
  final rects = <TextRect>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (var c = 0; c < line.text.length; c++) {
      buffer.write(line.text[c]);
      rects.add(
        TextRect(
          left: line.left + c * width,
          right: line.left + (c + 1) * width,
          bottom: line.baseline,
          top: line.baseline + height,
        ),
      );
    }
    if (i != lines.length - 1) {
      buffer.write('\n');
      rects.add(
        TextRect(left: 0, right: 0, bottom: line.baseline, top: line.baseline),
      );
    }
  }

  return PageText(fullText: buffer.toString(), charRects: rects);
}

void main() {
  group('lines', () {
    test('a line becomes a line', () {
      final lines = linesOf(page([(text: 'Hello', left: 10, baseline: 700)]));

      expect(lines.length, 1);
      expect(lines.single.text, 'Hello');
    });

    test('a break in the text starts a new line', () {
      final lines = linesOf(
        page([
          (text: 'One', left: 10, baseline: 700),
          (text: 'Two', left: 10, baseline: 680),
        ]),
      );

      expect(lines.map((l) => l.text), ['One', 'Two']);
    });

    test('spaces separate words', () {
      final line = linesOf(
        page([(text: 'Hello there Priya', left: 10, baseline: 700)]),
      ).single;

      expect(line.words.map((w) => w.text), ['Hello', 'there', 'Priya']);
    });

    // The word's box is where its own letters are, not where the line is.
    test('a word knows where it sits', () {
      final line = linesOf(
        page([(text: 'ab cd', left: 100, baseline: 700)]),
      ).single;

      expect(line.words[0].bounds.left, 100);
      expect(line.words[0].bounds.right, 112);
      expect(line.words[1].bounds.left, 118);
    });

    test('the line spans all of its words', () {
      final line = linesOf(
        page([(text: 'ab cd', left: 100, baseline: 700)]),
      ).single;

      expect(line.bounds.left, 100);
      expect(line.bounds.right, 130);
    });

    test('an empty page has no lines', () {
      expect(linesOf(const PageText(fullText: '', charRects: [])), isEmpty);
    });

    test('a line of only spaces is not a line', () {
      final lines = linesOf(
        page([
          (text: 'One', left: 10, baseline: 700),
          (text: '   ', left: 10, baseline: 680),
          (text: 'Two', left: 10, baseline: 660),
        ]),
      );

      expect(lines.map((l) => l.text), ['One', 'Two']);
    });
  });

  group('paragraphs', () {
    test('evenly spaced lines are one paragraph', () {
      final paragraphs = paragraphsOf(
        linesOf(
          page([
            (text: 'One', left: 10, baseline: 700),
            (text: 'Two', left: 10, baseline: 685),
            (text: 'Three', left: 10, baseline: 670),
          ]),
        ),
      );

      expect(paragraphs.length, 1);
      expect(paragraphs.single.text, 'One Two Three');
    });

    // The signal a person reads without thinking about it.
    test('a wider gap starts a new paragraph', () {
      final paragraphs = paragraphsOf(
        linesOf(
          page([
            (text: 'One', left: 10, baseline: 700),
            (text: 'Two', left: 10, baseline: 685),
            (text: 'Three', left: 10, baseline: 640),
            (text: 'Four', left: 10, baseline: 625),
          ]),
        ),
      );

      expect(paragraphs.length, 2);
      expect(paragraphs.first.text, 'One Two');
      expect(paragraphs.last.text, 'Three Four');
    });

    test('an indented line starts a new paragraph', () {
      final paragraphs = paragraphsOf(
        linesOf(
          page([
            (text: 'One', left: 10, baseline: 700),
            (text: 'Two', left: 10, baseline: 685),
            (text: 'Three', left: 40, baseline: 670),
          ]),
        ),
      );

      expect(paragraphs.length, 2);
      expect(paragraphs.last.text, 'Three');
    });

    // A line that starts slightly left of the one above is a justified line,
    // not a new paragraph.
    test('a line starting further left does not start one', () {
      final paragraphs = paragraphsOf(
        linesOf(
          page([
            (text: 'One', left: 40, baseline: 700),
            (text: 'Two', left: 10, baseline: 685),
          ]),
        ),
      );

      expect(paragraphs.length, 1);
    });

    test('a single line is a single paragraph', () {
      final paragraphs = paragraphsOf(
        linesOf(page([(text: 'Alone', left: 10, baseline: 700)])),
      );

      expect(paragraphs.single.text, 'Alone');
    });

    test('no lines make no paragraphs', () {
      expect(paragraphsOf(const []), isEmpty);
    });
  });

  group('columns', () {
    // A PDF has no notion of a cell. Two words a space apart are a phrase;
    // two words an inch apart are two columns.
    test('a wide gap splits a line into cells', () {
      final line = linesOf(
        page([(text: 'Item', left: 10, baseline: 700)]),
      ).single;
      final wide = TextLine(
        words: [
          ...line.words,
          const TextWord(
            text: 'Amount',
            bounds: TextRect(left: 300, right: 340, bottom: 700, top: 710),
          ),
        ],
        bounds: line.bounds,
      );

      expect(cellsOf(wide, columnGap: 50), ['Item', 'Amount']);
    });

    test('an ordinary space keeps words in one cell', () {
      final line = linesOf(
        page([(text: 'Total amount', left: 10, baseline: 700)]),
      ).single;

      expect(cellsOf(line, columnGap: 50), ['Total amount']);
    });

    test('a line with one word is one cell', () {
      final line = linesOf(
        page([(text: 'Total', left: 10, baseline: 700)]),
      ).single;

      expect(cellsOf(line, columnGap: 50), ['Total']);
    });

    // Derived from the page: six points separates columns in a ten-point
    // document and words in a thirty-point one.
    test('the threshold comes from the spacing on the page', () {
      final lines = linesOf(
        page([
          (text: 'a b c', left: 10, baseline: 700),
          (text: 'd e f', left: 10, baseline: 685),
        ]),
      );

      expect(columnGapFor(lines), closeTo(6 * 2.5, 0.01));
    });

    // Nothing to measure means nothing to split on. A threshold of zero would
    // make every word its own column.
    test('a page with no gaps to measure never splits', () {
      final lines = linesOf(page([(text: 'Alone', left: 10, baseline: 700)]));

      expect(columnGapFor(lines), double.infinity);
      expect(cellsOf(lines.single, columnGap: columnGapFor(lines)), ['Alone']);
    });
  });
}
