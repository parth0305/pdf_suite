import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/split_plan.dart';

void main() {
  // The sheet's live preview and its confirm-button enablement are exactly
  // this computation, so testing it here covers the behaviour directly.
  group('split preview', () {
    test('every page yields one output per page', () {
      expect(SplitPlan.everyPage(7).outputCount, 7);
    });

    test('valid ranges yield one output per range', () {
      expect(SplitPlan.parse('1-3,5', pageCount: 8).outputCount, 2);
    });

    test('invalid input surfaces a message rather than a count', () {
      expect(
        () => SplitPlan.parse('1-99', pageCount: 8),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('8'),
          ),
        ),
      );
    });

    test('an empty range keeps the confirm action unavailable', () {
      expect(() => SplitPlan.parse('', pageCount: 8), throwsFormatException);
    });
  });
}
