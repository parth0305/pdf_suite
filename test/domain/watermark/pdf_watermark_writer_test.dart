import 'dart:convert';
import 'dart:io';
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

/// Long enough that deflate beats the cost of declaring /Filter. A five-letter
/// mark does not, and must not be compressed - see the tests below.
const wordy = Watermark(
  text: 'CONFIDENTIAL DRAFT - NOT FOR DISTRIBUTION OR REVIEW',
);

/// Every stream in [out], inflated when its dictionary says /FlateDecode.
///
/// Reading the drawing commands straight out of the bytes stopped working the
/// moment watermark streams were compressed - which is the point: a test that
/// greps the output silently stops checking anything once the output is no
/// longer plain text.
typedef StreamEntry = ({int declaredLength, bool compressed, String content});

List<StreamEntry> streamsIn(Uint8List out) {
  final text = latin1.decode(out, allowInvalid: true);
  final streams = <StreamEntry>[];

  for (final m in RegExp(
    r'<< /Length (\d+)( /Filter /FlateDecode)? >>\nstream\n',
  ).allMatches(text)) {
    final declared = int.parse(m.group(1)!);
    final compressed = m.group(2) != null;
    final raw = out.sublist(m.end, m.end + declared);

    streams.add((
      declaredLength: declared,
      compressed: compressed,
      content: latin1.decode(
        compressed ? ZLibCodec().decode(raw) : raw,
        allowInvalid: true,
      ),
    ));
  }

  return streams;
}

void main() {
  test('the original bytes are still present, untouched', () {
    final original = twoPages();
    final out = writeWatermark(original, draft);

    expect(out.sublist(0, original.length), original);
  });

  // A watermark marks a document. On page one only it says nothing.
  test('every page is watermarked', () {
    final out = writeWatermark(twoPages(), draft);
    final text = latin1.decode(out, allowInvalid: true);

    expect(
      streamsIn(out).where((s) => s.content.contains('(DRAFT) Tj')).length,
      2,
      reason: 'one drawn watermark per page',
    );
    expect(text, contains('3 0 obj'));
    expect(text, contains('5 0 obj'));
  });

  test('a watermark stream worth compressing is compressed', () {
    final out = writeWatermark(twoPages(), wordy);
    final text = latin1.decode(out, allowInvalid: true);

    expect(RegExp(r'/Filter /FlateDecode').allMatches(text).length, 2);
    expect(
      text,
      isNot(contains('CONFIDENTIAL DRAFT')),
      reason: 'a compressed stream cannot be read out of the raw bytes',
    );
    expect(
      streamsIn(out).where((s) => s.content.contains('Tj')).length,
      2,
      reason: 'and it still inflates back to a drawn mark',
    );
  });

  // Compressing a short stream makes the document BIGGER once /Filter is
  // written into the dictionary. Watermarking must never grow a file more than
  // not compressing would.
  test('a short watermark stream is left raw', () {
    final out = writeWatermark(twoPages(), draft);

    expect(latin1.decode(out), isNot(contains('/FlateDecode')));
    expect(latin1.decode(out), contains('(DRAFT) Tj'));
  });

  test('compressing never makes the document larger', () {
    for (final mark in [draft, wordy]) {
      final compressed = writeWatermark(twoPages(), mark).length;
      final raw = _uncompressedLength(mark);

      expect(compressed, lessThanOrEqualTo(raw), reason: 'mark: ${mark.text}');
    }
  });

  // A /Length that describes the ORIGINAL text is the classic way to write a
  // stream no reader can parse: it reads past the end or stops short. The
  // fixture's own empty streams are in the output too, so this asks the
  // compressed ones specifically.
  test('a compressed stream declares the compressed length', () {
    final marks = streamsIn(
      writeWatermark(twoPages(), wordy),
    ).where((s) => s.compressed);

    expect(marks, hasLength(2));
    for (final s in marks) {
      expect(s.declaredLength, lessThan(s.content.length));
    }
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

/// What the document would weigh if every watermark stream were stored raw.
int _uncompressedLength(Watermark mark) {
  final out = writeWatermark(twoPages(), mark);

  return streamsIn(out)
      .where((s) => s.compressed)
      .fold(
        out.length,
        // Swapping a compressed stream for its raw text costs the difference in
        // bytes and refunds the /Filter declaration.
        (total, s) => total + s.content.length - s.declaredLength - 21,
      );
}
