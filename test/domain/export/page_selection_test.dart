import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/export/page_selection.dart';

void main() {
  group('parsePageRange', () {
    test('a single page', () {
      expect(parsePageRange('2', pageCount: 5), [1]);
    });

    test('a range', () {
      expect(parsePageRange('2-4', pageCount: 5), [1, 2, 3]);
    });

    test('a mixture', () {
      expect(parsePageRange('1, 3-4', pageCount: 5), [0, 2, 3]);
    });

    // Someone writing "9-" means "to the end", and refusing it would be
    // pedantry.
    test('an open end runs to the last page', () {
      expect(parsePageRange('3-', pageCount: 5), [2, 3, 4]);
    });

    test('duplicates collapse and order is restored', () {
      expect(parsePageRange('3, 1, 3, 2', pageCount: 5), [0, 1, 2]);
    });

    test('pages beyond the document are dropped', () {
      expect(parsePageRange('4-99', pageCount: 5), [3, 4]);
    });

    // Exporting nothing because of a typo is a worse failure than exporting
    // too much.
    test('an empty range means every page', () {
      expect(parsePageRange('', pageCount: 3), [0, 1, 2]);
      expect(parsePageRange('   ', pageCount: 3), [0, 1, 2]);
    });

    test('nonsense means every page rather than none', () {
      expect(parsePageRange('banana', pageCount: 3), [0, 1, 2]);
      expect(parsePageRange('0', pageCount: 3), [0, 1, 2]);
    });

    test('one-based in, zero-based out', () {
      expect(parsePageRange('1', pageCount: 3), [0]);
      expect(parsePageRange('3', pageCount: 3), [2]);
    });
  });

  group('bgraToRgba', () {
    // Getting this backwards swaps red and blue in every exported page, which
    // looks deliberate rather than broken.
    test('the channels are reordered and alpha kept', () {
      expect(bgraToRgba(const [10, 20, 30, 40]), [30, 20, 10, 40]);
    });

    test('a pure red BGRA pixel comes out red', () {
      expect(bgraToRgba(const [0, 0, 255, 255]), [255, 0, 0, 255]);
    });
  });

  group('pageImageName', () {
    test('the page number is in the name', () {
      expect(pageImageName('Invoice.pdf', 2, 9), 'Invoice page 2.png');
    });

    // A folder of exported pages should sort the way the document reads.
    test('numbers are padded so ten sorts after nine', () {
      final names = [
        pageImageName('Doc.pdf', 9, 12),
        pageImageName('Doc.pdf', 10, 12),
      ];

      expect(names, ['Doc page 09.png', 'Doc page 10.png']);
      expect(names[0].compareTo(names[1]), lessThan(0));
    });

    test('the .pdf extension is replaced, not appended to', () {
      expect(pageImageName('Report.PDF', 1, 1), 'Report page 1.png');
      expect(pageImageName('Report.PDF', 1, 1), isNot(contains('.PDF')));
    });
  });
}
