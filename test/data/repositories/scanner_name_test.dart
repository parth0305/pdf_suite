import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/repositories/scanner_repository_impl.dart';

void main() {
  group('scannedName', () {
    test('names a scan by when it was taken', () {
      expect(
        scannedName(DateTime(2026, 8, 27, 14, 5, 9)),
        'Scan 2026-08-27 140509.pdf',
      );
    });

    // Two scans a second apart must not collide into one name; the library
    // would show two rows that look identical.
    test('a second apart produces different names', () {
      expect(
        scannedName(DateTime(2026, 8, 27, 14, 5, 9)),
        isNot(scannedName(DateTime(2026, 8, 27, 14, 5, 10))),
      );
    });

    test('single-digit parts are padded, so names sort chronologically', () {
      final early = scannedName(DateTime(2026, 1, 2, 3, 4, 5));
      final late_ = scannedName(DateTime(2026, 11, 12, 13, 14, 15));

      expect(early, 'Scan 2026-01-02 030405.pdf');
      expect(
        early.compareTo(late_),
        lessThan(0),
        reason: 'padding is what makes string order match time order',
      );
    });
  });
}
