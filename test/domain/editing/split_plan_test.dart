import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/split_plan.dart';

void main() {
  group('everyPage', () {
    test('produces one output per page', () {
      final plan = SplitPlan.everyPage(3);
      expect(plan.groups, [
        [0],
        [1],
        [2],
      ]);
      expect(plan.outputCount, 3);
    });

    test('a single-page document yields one output', () {
      expect(SplitPlan.everyPage(1).groups, [
        [0],
      ]);
    });
  });

  group('parse', () {
    // Users type 1-based page numbers; everything downstream is 0-based.
    test('a single range converts to zero-based indices', () {
      expect(SplitPlan.parse('1-3', pageCount: 5).groups, [
        [0, 1, 2],
      ]);
    });

    test('comma-separated ranges become separate outputs', () {
      expect(SplitPlan.parse('1-2,4-5', pageCount: 5).groups, [
        [0, 1],
        [3, 4],
      ]);
    });

    test('a bare page number is a single-page group', () {
      expect(SplitPlan.parse('3', pageCount: 5).groups, [
        [2],
      ]);
    });

    test('mixed ranges and single pages', () {
      expect(SplitPlan.parse('1-2,4,6', pageCount: 6).groups, [
        [0, 1],
        [3],
        [5],
      ]);
    });

    test('whitespace is ignored', () {
      expect(SplitPlan.parse(' 1 - 2 , 4 ', pageCount: 5).groups, [
        [0, 1],
        [3],
      ]);
    });

    test('overlapping ranges are allowed and produce both outputs', () {
      expect(SplitPlan.parse('1-3,2-4', pageCount: 5).groups, [
        [0, 1, 2],
        [1, 2, 3],
      ]);
    });

    test('empty input is rejected', () {
      expect(() => SplitPlan.parse('', pageCount: 5), throwsFormatException);
      expect(() => SplitPlan.parse('   ', pageCount: 5), throwsFormatException);
    });

    test('a page beyond the document is rejected', () {
      expect(() => SplitPlan.parse('1-9', pageCount: 5), throwsFormatException);
      expect(() => SplitPlan.parse('7', pageCount: 5), throwsFormatException);
    });

    test('page zero is rejected because input is one-based', () {
      expect(() => SplitPlan.parse('0-2', pageCount: 5), throwsFormatException);
    });

    test('a descending range is rejected', () {
      expect(() => SplitPlan.parse('4-2', pageCount: 5), throwsFormatException);
    });

    test('non-numeric input is rejected', () {
      expect(
        () => SplitPlan.parse('one-two', pageCount: 5),
        throwsFormatException,
      );
      expect(() => SplitPlan.parse('1-', pageCount: 5), throwsFormatException);
    });

    test('the failure message names the problem', () {
      expect(
        () => SplitPlan.parse('1-9', pageCount: 5),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('5'),
          ),
        ),
      );
    });
  });
}
