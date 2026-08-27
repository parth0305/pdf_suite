import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/viewer/widgets/custom_stamp_dialog.dart';

void main() {
  group('formatStampDate', () {
    // A date someone would write on a document, not an ISO timestamp.
    test('reads as a person would write it', () {
      expect(formatStampDate(DateTime(2026, 8, 28)), '28 Aug 2026');
    });

    test('single-digit days are not padded', () {
      expect(formatStampDate(DateTime(2026, 1, 5)), '5 Jan 2026');
    });

    test('every month maps to its own name', () {
      final names = [
        for (var m = 1; m <= 12; m++) formatStampDate(DateTime(2026, m, 1)),
      ];

      expect(names.toSet(), hasLength(12), reason: 'no month repeats');
      expect(names.first, contains('Jan'));
      expect(names.last, contains('Dec'));
    });
  });
}
