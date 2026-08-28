import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/numbering/page_numbers.dart';

const a4 = TextRect(left: 0, right: 595, top: 842, bottom: 0);

void main() {
  group('what the number says', () {
    test('plain is just the number', () {
      expect(numberTextFor(const PageNumbering(), 0, 3), '1');
      expect(numberTextFor(const PageNumbering(), 2, 3), '3');
    });

    test('the other formats', () {
      const at = 1;
      expect(
        numberTextFor(
          const PageNumbering(format: NumberFormat.labelled),
          at,
          3,
        ),
        'Page 2',
      );
      expect(
        numberTextFor(const PageNumbering(format: NumberFormat.ofTotal), at, 3),
        '2 of 3',
      );
      expect(
        numberTextFor(
          const PageNumbering(format: NumberFormat.labelledOfTotal),
          at,
          3,
        ),
        'Page 2 of 3',
      );
    });

    // A chapter continuing from another document starts at 47, not 1.
    test('numbering can start anywhere', () {
      expect(numberTextFor(const PageNumbering(startAt: 47), 0, 3), '47');
      expect(numberTextFor(const PageNumbering(startAt: 47), 2, 3), '49');
    });

    group('skipping the first page', () {
      const skipping = PageNumbering(skipFirst: true);

      test('the title page gets nothing', () {
        expect(numberTextFor(skipping, 0, 5), isNull);
      });

      // The numbering starts where the NUMBERS start. A second page reading
      // "2" when page one was deliberately left out is the bug here.
      test('the page after it is page one', () {
        expect(numberTextFor(skipping, 1, 5), '1');
        expect(numberTextFor(skipping, 2, 5), '2');
      });

      test('the total excludes the skipped page', () {
        expect(
          numberTextFor(
            const PageNumbering(skipFirst: true, format: NumberFormat.ofTotal),
            1,
            5,
          ),
          '1 of 4',
        );
      });

      test('it composes with a starting number', () {
        expect(
          numberTextFor(
            const PageNumbering(skipFirst: true, startAt: 10),
            1,
            5,
          ),
          '10',
        );
      });
    });
  });

  group('where the number goes', () {
    test('bottom centre is centred and above the edge', () {
      final origin = numberOrigin(const PageNumbering(), '12', a4);

      expect(origin.x, closeTo(595 / 2 - estimatedWidth('12', 10) / 2, 0.01));
      expect(origin.y, 36);
    });

    test('bottom right sits inside the margin', () {
      final origin = numberOrigin(
        const PageNumbering(position: NumberPosition.bottomRight),
        '12',
        a4,
      );

      expect(origin.x, closeTo(595 - 36 - estimatedWidth('12', 10), 0.01));
      expect(origin.x, lessThan(595 - 36));
    });

    test('bottom left is at the margin', () {
      expect(
        numberOrigin(
          const PageNumbering(position: NumberPosition.bottomLeft),
          '12',
          a4,
        ).x,
        36,
      );
    });

    // Text is drawn from its baseline. Without subtracting the font size a
    // top-positioned number sits half off the page.
    test('a top position drops by the font size', () {
      final origin = numberOrigin(
        const PageNumbering(position: NumberPosition.topCentre),
        '12',
        a4,
      );

      expect(origin.y, 842 - 36 - 10);
      expect(origin.y, lessThan(842 - 36));
    });

    test('a longer number stays inside the right margin', () {
      final origin = numberOrigin(
        const PageNumbering(
          position: NumberPosition.bottomRight,
          format: NumberFormat.labelledOfTotal,
        ),
        'Page 100 of 200',
        a4,
      );

      expect(
        origin.x + estimatedWidth('Page 100 of 200', 10),
        closeTo(595 - 36, 0.01),
      );
    });
  });

  group('the content stream', () {
    // An unbalanced graphics state corrupts everything drawn after it.
    test('q and Q are balanced', () {
      final stream = pageNumberContentStream(
        const PageNumbering(),
        '3',
        mediaBox: a4,
      );

      expect(RegExp(r'\bq\b').allMatches(stream).length, 1);
      expect(RegExp(r'\bQ\b').allMatches(stream).length, 1);
      expect(RegExp(r'\bBT\b').allMatches(stream).length, 1);
      expect(RegExp(r'\bET\b').allMatches(stream).length, 1);
    });

    test('it names the numbering font and draws the text', () {
      final stream = pageNumberContentStream(
        const PageNumbering(),
        'Page 3 of 9',
        mediaBox: a4,
      );

      expect(stream, contains('/PgF1 10 Tf'));
      expect(stream, contains('(Page 3 of 9) Tj'));
    });
  });
}
