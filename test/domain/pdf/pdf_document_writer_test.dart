import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

const source =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\n'
    'endobj\n'
    'xref\n0 4\n0000000000 65535 f \n'
    'trailer\n<< /Size 4 /Root 1 0 R /Info 9 0 R >>\n'
    'startxref\n9\n%%EOF\n';

List<int> bytesOf(String s) => latin1.encode(s);

String rewritten() => latin1.decode(
  writePdfDocument(bytesOf(source), parsePdfObjects(bytesOf(source))),
);

void main() {
  test('emits every object it was given', () {
    final out = rewritten();

    for (final n in [1, 2, 3]) {
      expect(out, contains('$n 0 obj'), reason: 'object $n');
    }
  });

  test('carries /Root and /Info into the new trailer', () {
    final out = rewritten();

    expect(out, contains('/Root 1 0 R'));
    expect(out, contains('/Info 9 0 R'));
  });

  // This is a rewrite, not an incremental update. A /Prev would point at a
  // cross-reference table that no longer exists in the new file.
  test('the trailer has no /Prev', () {
    expect(rewritten(), isNot(contains('/Prev')));
  });

  test('starts with a PDF header and ends with EOF', () {
    final out = rewritten();

    expect(out.startsWith('%PDF-'), isTrue);
    expect(out.trimRight().endsWith('%%EOF'), isTrue);
  });

  test('the xref offsets point at the objects', () {
    final out = rewritten();
    // Not lastIndexOf('xref') - that matches the one inside `startxref`,
    // which sits after the table.
    final xrefAt = out.lastIndexOf('\nxref\n');
    final entries = RegExp(
      r'^(\d{10}) 00000 n $',
      multiLine: true,
    ).allMatches(out.substring(xrefAt)).toList();

    expect(entries, hasLength(3));
    for (final e in entries) {
      final offset = int.parse(e.group(1)!);
      // An offset that does not land on `N G obj` is a broken xref, and a
      // reader will refuse the file or silently lose the object.
      expect(
        RegExp(r'^\d+ \d+ obj').hasMatch(out.substring(offset)),
        isTrue,
        reason: 'offset $offset should point at an object header',
      );
    }
  });

  test('a document with no objects is refused', () {
    expect(
      () => writePdfDocument(bytesOf('%PDF-1.4\n'), const []),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  test('a document with no /Root is refused', () {
    const noRoot = '1 0 obj\n<< >>\nendobj\ntrailer\n<< /Size 2 >>\n%%EOF\n';
    expect(
      () => writePdfDocument(bytesOf(noRoot), parsePdfObjects(bytesOf(noRoot))),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });
}
