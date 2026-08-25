import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';

String pdfWith(String pageDict) =>
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n$pageDict\nendobj\n'
    'xref\n0 4\n0000000000 65535 f \n'
    'trailer\n<< /Size 4 /Root 1 0 R >>\n'
    'startxref\n9\n%%EOF\n';

void main() {
  group('pageAt', () {
    test('finds a page whose /Type is first', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>'),
      );
      expect(r.pageAt(0)!.objectNumber, 3);
    });

    // The spike's regex failed here: a '>' appears before /Type.
    test(
      'finds a page whose /Type is NOT first, after nested dictionaries',
      () {
        final r = PdfObjectReader.parse(
          pdfWith(
            '<< /Resources << /Font << /F1 9 0 R >> >> '
            '/MediaBox [0 0 595 842] /Type /Page /Parent 2 0 R >>',
          ),
        );
        expect(r.pageAt(0)!.objectNumber, 3);
      },
    );

    test('does not mistake /Pages for /Page', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R >>'),
      );
      expect(r.pageAt(1), isNull, reason: 'only one real page');
    });

    test('returns null for a page index that does not exist', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R >>'),
      );
      expect(r.pageAt(5), isNull);
    });

    test('malformed input yields no pages rather than throwing', () {
      expect(PdfObjectReader.parse('not a pdf').pageAt(0), isNull);
    });
  });

  group('existingAnnotRefs', () {
    test('is empty when the page has no /Annots', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R >>'),
      );
      expect(r.pageAt(0)!.existingAnnotRefs, isEmpty);
    });

    // Replacing rather than merging would silently delete a user's existing
    // annotations - the worst possible bug in this file.
    test('reads an existing /Annots array', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R /Annots [7 0 R 8 0 R] >>'),
      );
      expect(r.pageAt(0)!.existingAnnotRefs, ['7 0 R', '8 0 R']);
    });

    test('reads a single-entry /Annots array', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Annots [7 0 R] /Parent 2 0 R >>'),
      );
      expect(r.pageAt(0)!.existingAnnotRefs, ['7 0 R']);
    });
  });

  group('withAnnots', () {
    test('adds /Annots to a page that had none', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R >>'),
      );
      final out = r.withAnnots(r.pageAt(0)!, ['9 0 R']);

      expect(out, contains('/Annots [9 0 R]'));
      expect(out, contains('/Type /Page'));
      expect(out.trim().endsWith('>>'), isTrue);
    });

    test('merges with existing refs rather than replacing them', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Annots [7 0 R] /Parent 2 0 R >>'),
      );
      final out = r.withAnnots(r.pageAt(0)!, ['9 0 R']);

      expect(out, contains('7 0 R'));
      expect(out, contains('9 0 R'));
      expect(
        '/Annots'.allMatches(out).length,
        1,
        reason: 'exactly one /Annots',
      );
    });

    test('preserves nested dictionaries untouched', () {
      final r = PdfObjectReader.parse(
        pdfWith(
          '<< /Type /Page /Resources << /Font << /F1 9 0 R >> >> '
          '/Parent 2 0 R >>',
        ),
      );
      final out = r.withAnnots(r.pageAt(0)!, ['9 0 R']);

      expect(out, contains('/Resources << /Font << /F1 9 0 R >> >>'));
    });
  });

  group('usesXrefStream', () {
    test('a classic table is not an xref stream', () {
      expect(
        PdfObjectReader.parse(
          pdfWith('<< /Type /Page /Parent 2 0 R >>'),
        ).usesXrefStream,
        isFalse,
      );
    });

    // Refusing loudly beats producing a document whose annotations never show.
    test('detects a cross-reference stream document', () {
      const xrefStreamPdf =
          '%PDF-1.5\n'
          '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
          '4 0 obj\n<< /Type /XRef /Size 5 /W [1 2 1] >>\nstream\n\nendstream\nendobj\n'
          'startxref\n9\n%%EOF\n';
      expect(PdfObjectReader.parse(xrefStreamPdf).usesXrefStream, isTrue);
    });
  });
}
