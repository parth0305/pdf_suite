import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/archive/pdfa_check.dart';

import '../../../scripts/pdf_fixture_builder.dart';

String plain() =>
    latin1.decode(buildPdf(generatedPages(1)), allowInvalid: true);

PdfaReport check(String text) => checkPdfa(text);

void main() {
  // The generated fixture uses Helvetica without embedding it, which is the
  // commonest reason a real document is not PDF/A.
  test('a font that is named but not carried blocks conversion', () {
    final report = check(plain());

    expect(report.canConvert, isFalse);
    expect(report.blockers[PdfaIssue.fontNotEmbedded], contains('Helvetica'));
  });

  test('an embedded font does not block', () {
    final text = plain().replaceFirst(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
          '/FontDescriptor 20 0 R >>\nendobj\n'
          '20 0 obj\n<< /Type /FontDescriptor /FontFile2 21 0 R >>',
    );

    expect(check(text).blockers[PdfaIssue.fontNotEmbedded], isNull);
  });

  // A Type 0 font's descriptor is on its descendant. Looking only at the font
  // itself calls every embedded CID font unembedded.
  test("a composite font's descendant is where the program is", () {
    final text = plain().replaceFirst(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      '<< /Type /Font /Subtype /Type0 /BaseFont /Noto '
          '/DescendantFonts [20 0 R] >>\nendobj\n'
          '20 0 obj\n<< /Type /Font /FontDescriptor 21 0 R >>\nendobj\n'
          '21 0 obj\n<< /Type /FontDescriptor /FontFile2 22 0 R >>',
    );

    expect(check(text).blockers[PdfaIssue.fontNotEmbedded], isNull);
  });

  test('a document with no fonts at all can convert', () {
    final text = latin1
        .decode(buildPdf(generatedPages(1), omitText: true), allowInvalid: true)
        .replaceFirst(
          '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
          '<< /Type /XObject >>',
        );

    expect(check(text).canConvert, isTrue);
  });

  test('encryption blocks conversion', () {
    final text = plain().replaceFirst(
      '/Root 1 0 R',
      '/Root 1 0 R /Encrypt 9 0 R',
    );

    expect(check(text).blockers.containsKey(PdfaIssue.encrypted), isTrue);
  });

  test('LZW blocks conversion', () {
    final text = plain().replaceFirst(
      '<< /Length ',
      '<< /Filter /LZWDecode /Length ',
    );

    expect(check(text).blockers.containsKey(PdfaIssue.lzwCompression), isTrue);
  });

  test('a stream whose data is in another file blocks conversion', () {
    final text = plain().replaceFirst(
      '<< /Length ',
      '<< /F (other.dat) /Length ',
    );

    expect(check(text).blockers.containsKey(PdfaIssue.externalStream), isTrue);
  });

  // /F on an annotation is its flag field, not a file. Confusing the two
  // refuses every document carrying a printable annotation.
  test("an annotation's flags are not an external file", () {
    final text = plain().replaceFirst(
      '/Type /Catalog',
      '/Type /Catalog /Annot << /Subtype /Square /F 4 >>',
    );

    expect(check(text).blockers.containsKey(PdfaIssue.externalStream), isFalse);
  });

  // An attached file's /Filespec also carries /F (name). Treating that as an
  // external stream would REFUSE a document that only needs the attachment
  // taken out.
  test('an attached file is a removal, not a blocker', () {
    final text = plain().replaceFirst(
      '/Type /Catalog',
      '/Type /Catalog /X << /Type /Filespec /F (notes.txt) >>',
    );

    expect(check(text).blockers.containsKey(PdfaIssue.externalStream), isFalse);
  });

  group('things that are removed rather than refused', () {
    test('JavaScript is removed', () {
      final text = latin1.decode(
        buildPdf(generatedPages(1), extraCatalogEntries: kJavaScriptNames),
        allowInvalid: true,
      );

      expect(check(text).removals, contains(PdfaIssue.javaScript));
    });

    test('an attached file is removed', () {
      final text = plain().replaceFirst(
        '/Type /Catalog',
        '/Type /Catalog /X << /Type /Filespec /F (notes.txt) >>',
      );

      expect(check(text).removals, contains(PdfaIssue.embeddedFile));
    });

    test('/NeedAppearances is turned off', () {
      final text = plain().replaceFirst(
        '/Type /Catalog',
        '/Type /Catalog /AcroForm << /NeedAppearances true >>',
      );

      expect(check(text).removals, contains(PdfaIssue.needAppearances));
    });

    // A removal is not a refusal: the document still converts.
    test('a removal alone does not block conversion', () {
      final text = latin1.decode(
        buildPdf(
          generatedPages(1),
          omitText: true,
          extraCatalogEntries: kJavaScriptNames,
        ),
        allowInvalid: true,
      );

      expect(check(text).canConvert, isTrue);
      expect(check(text).removals, isNotEmpty);
    });
  });
}
