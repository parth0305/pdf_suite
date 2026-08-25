import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_annotation_writer.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';

Uint8List classicPdf() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\nendobj\n'
    'xref\n0 4\n0000000000 65535 f \n'
    'trailer\n<< /Size 4 /Root 1 0 R >>\n'
    'startxref\n9\n%%EOF\n',
  ),
);

TextMarkup markup([MarkupKind kind = MarkupKind.highlight]) => TextMarkup(
  kind: kind,
  pageIndex: 0,
  quads: const [TextRect(left: 60, top: 712, right: 120, bottom: 700)],
);

void main() {
  test('leaves the original bytes untouched at the front', () {
    final original = classicPdf();
    final out = writeMarkup(original, [markup()]);

    expect(out.length, greaterThan(original.length));
    expect(out.sublist(0, original.length), original);
  });

  test('emits the annotation with the right subtype and quads', () {
    final text = latin1.decode(writeMarkup(classicPdf(), [markup()]));

    expect(text, contains('/Subtype /Highlight'));
    expect(text, contains('/QuadPoints'));
    expect(text, contains('60 712 120 712 60 700 120 700'));
  });

  test('emits an appearance stream', () {
    final text = latin1.decode(writeMarkup(classicPdf(), [markup()]));
    expect(text, contains('/Subtype /Form'));
    expect(text, contains('/AP'));
  });

  test('the page object is overridden with /Annots', () {
    final text = latin1.decode(writeMarkup(classicPdf(), [markup()]));
    final defs = RegExp(r'3 0 obj(.*?)endobj', dotAll: true).allMatches(text);
    expect(defs.last.group(1), contains('/Annots'));
  });

  test('ends with a trailer chaining to the previous xref', () {
    final text = latin1.decode(writeMarkup(classicPdf(), [markup()]));
    expect(text, contains('/Prev 9'));
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
  });

  test('writes several markups of different kinds', () {
    final text = latin1.decode(
      writeMarkup(classicPdf(), [
        markup(),
        markup(MarkupKind.underline),
        markup(MarkupKind.strikeOut),
      ]),
    );

    expect(text, contains('/Subtype /Highlight'));
    expect(text, contains('/Subtype /Underline'));
    expect(text, contains('/Subtype /StrikeOut'));
  });

  test('overrides the page once however many markups it carries', () {
    final text = latin1.decode(
      writeMarkup(classicPdf(), [markup(), markup(MarkupKind.underline)]),
    );
    // Original definition plus exactly one override.
    expect(RegExp(r'3 0 obj').allMatches(text).length, 2);
  });

  test('an empty markup list returns the document unchanged', () {
    final original = classicPdf();
    expect(writeMarkup(original, const []), original);
  });

  // Refusing loudly beats producing a file whose annotations never appear.
  test('a cross-reference-stream document is refused', () {
    final xrefStream = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.5\n'
        '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        '4 0 obj\n<< /Type /XRef /Size 5 >>\nstream\n\nendstream\nendobj\n'
        'startxref\n9\n%%EOF\n',
      ),
    );

    expect(
      () => writeMarkup(xrefStream, [markup()]),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  test('a document with no page object is refused', () {
    final noPages = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        'trailer\n<< /Size 2 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
      ),
    );

    expect(
      () => writeMarkup(noPages, [markup()]),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });
}
