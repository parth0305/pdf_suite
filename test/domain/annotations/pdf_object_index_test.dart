import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';

void main() {
  test('indexes objects by number', () {
    final index = PdfObjectIndex.parse(
      '%PDF-1.4\n'
      '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
      '7 0 obj\n<< /Type /Annot /Subtype /Ink >>\nendobj\n',
    );

    expect(index.bodyOf(1), contains('/Catalog'));
    expect(index.bodyOf(7), contains('/Ink'));
    expect(index.bodyOf(99), isNull);
  });

  // Incremental updates append a NEW definition of an existing object. A
  // reader walking the trailer chain backwards sees the LAST one; reading the
  // superseded copy is what orphaned annotations before PR #6.
  test('the last definition of an object number wins', () {
    final index = PdfObjectIndex.parse(
      '3 0 obj\n<< /Type /Page >>\nendobj\n'
      '3 0 obj\n<< /Type /Page /Annots [7 0 R] >>\nendobj\n',
    );

    expect(index.bodyOf(3), contains('/Annots'));
  });

  test('object numbers are listed in first-appearance order', () {
    final index = PdfObjectIndex.parse(
      '5 0 obj\n<< >>\nendobj\n'
      '2 0 obj\n<< >>\nendobj\n'
      '5 0 obj\n<< /Again true >>\nendobj\n',
    );

    expect(index.objectNumbers, [5, 2]);
  });

  // A nested dictionary must not end the outer one early.
  test('nested dictionaries do not terminate the outer one', () {
    final index = PdfObjectIndex.parse(
      '4 0 obj\n<< /AP << /N 9 0 R >> /F 4 >>\nendobj\n',
    );

    expect(index.bodyOf(4), contains('/F 4'));
  });

  test('detects cross-reference streams', () {
    expect(
      PdfObjectIndex.parse(
        '4 0 obj\n<< /Type /XRef >>\nendobj\n',
      ).usesXrefStream,
      isTrue,
    );
    expect(
      PdfObjectIndex.parse(
        '4 0 obj\n<< /Type /Page >>\nendobj\n',
      ).usesXrefStream,
      isFalse,
    );
  });

  test('an object with no dictionary is skipped, not crashed on', () {
    final index = PdfObjectIndex.parse('9 0 obj\n[7 0 R]\nendobj\n');
    expect(index.bodyOf(9), isNull);
  });
}
