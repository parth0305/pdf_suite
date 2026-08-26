import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/pdf/pdf_permissions.dart';

void main() {
  test('everything allowed clears only the reserved bits', () {
    // -4 is all ones with bits 1 and 2 cleared.
    expect(PdfPermissions.all.bits, -4);
  });

  test('the reserved low bits are always zero', () {
    for (final p in [
      PdfPermissions.all,
      const PdfPermissions(printing: false),
      const PdfPermissions(copying: false, modifying: false),
    ]) {
      expect(p.bits & 1, 0);
      expect(p.bits & 2, 0);
    }
  });

  test(
    'denying a permission clears its bit and nothing else it should keep',
    () {
      expect(const PdfPermissions(copying: false).bits & 16, 0);
      expect(
        const PdfPermissions(copying: false).bits & 4,
        4,
        reason: 'printing is untouched',
      );
    },
  );

  // A viewer that honours high-quality printing but not printing would be
  // absurd, so the dependent bits come down together.
  test('denying printing also denies high-quality printing', () {
    final bits = const PdfPermissions(printing: false).bits;

    expect(bits & 4, 0);
    expect(bits & 2048, 0);
  });

  test('denying modifying also denies assembling', () {
    final bits = const PdfPermissions(modifying: false).bits;

    expect(bits & 8, 0);
    expect(bits & 1024, 0);
  });

  test('denying annotating also denies filling form fields', () {
    final bits = const PdfPermissions(annotating: false).bits;

    expect(bits & 32, 0);
    expect(bits & 256, 0);
  });

  test('high bits stay set so the value is a valid /P', () {
    expect(const PdfPermissions(printing: false).bits & (1 << 20), 1 << 20);
  });
}
