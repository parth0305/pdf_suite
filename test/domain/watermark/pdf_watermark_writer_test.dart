import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/watermark/pdf_watermark_writer.dart';
import 'package:folio/domain/watermark/watermark.dart';

Uint8List twoPages() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n'
    '4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n'
    '5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>\nendobj\n'
    '6 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n'
    'xref\n0 7\n0000000000 65535 f \n'
    'trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

const draft = Watermark(text: 'DRAFT');

void main() {
  test('the original bytes are still present, untouched', () {
    final original = twoPages();
    final out = writeWatermark(original, draft);

    expect(out.sublist(0, original.length), original);
  });

  // A watermark marks a document. On page one only it says nothing.
  test('every page is watermarked', () {
    final text = latin1.decode(writeWatermark(twoPages(), draft));

    expect(RegExp(r'\(DRAFT\) Tj').allMatches(text).length, 2);
    expect(text, contains('3 0 obj'));
    expect(text, contains('5 0 obj'));
  });

  test('the font and graphics state are emitted once, not per page', () {
    final text = latin1.decode(writeWatermark(twoPages(), draft));

    expect(RegExp(r'/BaseFont /Helvetica').allMatches(text).length, 1);
    expect(RegExp(r'/Type /ExtGState').allMatches(text).length, 1);
  });

  test('each page references the watermark stream', () {
    final text = latin1.decode(writeWatermark(twoPages(), draft));
    expect(RegExp(r'/Contents \[\d+ 0 R \d+ 0 R\]').allMatches(text).length, 2);
  });

  test('a cross-reference-stream document is refused', () {
    final modern = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.5\n'
        '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        '4 0 obj\n<< /Type /XRef /Size 5 >>\nstream\n\nendstream\nendobj\n'
        'startxref\n9\n%%EOF\n',
      ),
    );

    expect(
      () => writeWatermark(modern, draft),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  test('empty text is refused rather than stamping nothing', () {
    expect(
      () => writeWatermark(twoPages(), const Watermark(text: '   ')),
      throwsA(isA<ArgumentError>()),
    );
  });
}
