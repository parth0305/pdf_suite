import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
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

  group('incremental updates', () {
    // A document annotated once, then annotated again. The original page
    // dictionary comes FIRST in the file and the override carrying /Annots is
    // appended after it. Reading the original means merging into an empty
    // /Annots, which orphans the first annotation - it stays in the file but
    // stops rendering. That is silent data loss.
    const annotatedTwice =
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\n'
        'endobj\n'
        'xref\n0 4\n0000000000 65535 f \n'
        'trailer\n<< /Size 4 /Root 1 0 R >>\n'
        'startxref\n9\n%%EOF\n'
        // --- incremental update: page 3 now carries an annotation ---
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Annots [7 0 R] >>\nendobj\n'
        'xref\n3 1\n0000000200 00000 n \n'
        'trailer\n<< /Size 8 /Root 1 0 R /Prev 9 >>\n'
        'startxref\n300\n%%EOF\n';

    test('the LAST definition of a page object wins', () {
      final page = PdfObjectReader.parse(annotatedTwice).pageAt(0)!;

      expect(
        page.existingAnnotRefs,
        ['7 0 R'],
        reason:
            'reading the superseded dictionary orphans the first annotation',
      );
    });

    test('an override does not add a phantom extra page', () {
      final reader = PdfObjectReader.parse(annotatedTwice);

      expect(reader.pageAt(0), isNotNull);
      expect(
        reader.pageAt(1),
        isNull,
        reason: 'one page defined twice is still one page',
      );
    });

    test('merging preserves the earlier annotation', () {
      final reader = PdfObjectReader.parse(annotatedTwice);
      final merged = reader.withAnnots(reader.pageAt(0)!, ['9 0 R']);

      expect(merged, contains('7 0 R'));
      expect(merged, contains('9 0 R'));
    });
  });

  group('annotation arrays this reader cannot safely merge', () {
    // Other producers commonly write /Annots as an indirect reference. Our
    // merge emits an inline array, which would REPLACE that reference and
    // orphan every annotation the other tool wrote. Refusing is the only safe
    // answer until the reader can resolve indirect arrays.
    test('an indirect /Annots is refused, not silently replaced', () {
      const indirect =
          '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R /Annots 9 0 R >>\nendobj\n'
          '9 0 obj\n[7 0 R 8 0 R]\nendobj\n'
          'trailer\n<< /Size 10 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      expect(
        () => PdfObjectReader.parse(indirect),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });

    test('a page with no /Annots at all is still fine', () {
      const plain =
          '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n'
          'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      expect(
        PdfObjectReader.parse(plain).pageAt(0)!.existingAnnotRefs,
        isEmpty,
      );
    });
  });

  group('withContentsAndResources', () {
    String rewrite(String dict) {
      final reader = PdfObjectReader.parse(pdfWith(dict));
      return reader.withContentsAndResources(
        reader.pageAt(0)!,
        contentObjectNumber: 20,
        fontObjectNumber: 21,
        extGStateObjectNumber: 22,
      );
    }

    test('a single /Contents reference becomes an array', () {
      final out = rewrite('<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>');
      expect(out, contains('/Contents [4 0 R 20 0 R]'));
    });

    test('an existing /Contents array is appended to', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R /Contents [4 0 R 5 0 R] >>',
      );
      expect(out, contains('/Contents [4 0 R 5 0 R 20 0 R]'));
    });

    test('a page with no /Contents gains one', () {
      final out = rewrite('<< /Type /Page /Parent 2 0 R >>');
      expect(out, contains('/Contents [20 0 R]'));
    });

    test('a page with no /Resources gains them', () {
      final out = rewrite('<< /Type /Page /Parent 2 0 R >>');

      expect(out, contains('/WMF1 21 0 R'));
      expect(out, contains('/WMGS 22 0 R'));
    });

    // Replacing a page's /Resources strips the fonts its own content depends
    // on, and the page renders blank.
    test('existing /Resources survive the merge', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R '
        '/Resources << /Font << /F1 9 0 R >> >> >>',
      );

      expect(out, contains('/F1 9 0 R'), reason: 'the page own font');
      expect(out, contains('/WMF1 21 0 R'), reason: 'ours');
    });

    test('an existing /ExtGState entry survives too', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R '
        '/Resources << /ExtGState << /GS0 8 0 R >> >> >>',
      );

      expect(out, contains('/GS0 8 0 R'));
      expect(out, contains('/WMGS 22 0 R'));
    });

    test('other page keys are left alone', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Rotate 90 /Contents 4 0 R >>',
      );

      expect(out, contains('/MediaBox [0 0 595 842]'));
      expect(out, contains('/Rotate 90'));
    });
  });
}
