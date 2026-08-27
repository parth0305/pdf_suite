import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/ocr/pdf_ocr_writer.dart';

/// Page 3 already has a font and an image in /Resources, so merging can be
/// told apart from replacing. Page 5 has neither.
Uint8List source() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
    '/Resources << /Font << /F1 9 0 R >> /XObject << /Im0 8 0 R >> >> >>\n'
    'endobj\n'
    '4 0 obj\n<< /Length 9 >>\nstream\nPAGE-BODY\nendstream\nendobj\n'
    '5 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n'
    'xref\n0 6\n0000000000 65535 f \n'
    'trailer\n<< /Size 6 /Root 1 0 R /Info 7 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

String out(Map<int, String> layers) =>
    latin1.decode(writeOcrLayer(source(), layers), allowInvalid: true);

const layer = 'BT 3 Tr /OcF1 12 Tf 1 0 0 1 10 20 Tm (Invoice) Tj ET\n';

void main() {
  // Nothing is removed, so the original bytes staying at the front of the file
  // is exactly right - the opposite of redaction.
  test('the original bytes are untouched', () {
    final original = source();
    final result = writeOcrLayer(original, {0: layer});

    expect(result.sublist(0, original.length), original);
  });

  test('the new trailer chains to the previous one', () {
    final result = out({0: layer});
    final lastTrailer = result.substring(result.lastIndexOf('trailer'));

    expect(lastTrailer, contains('/Prev 9'));
  });

  // A trailer without /Info discards the document's title and author. This
  // exact bug was found in already-merged code once.
  //
  // It must be asserted on the LAST trailer. The original bytes stay at the
  // front of an incremental update, so a plain `contains` finds the original
  // /Info and passes even when the new trailer drops it - which is exactly
  // what happened when this was mutated.
  test('/Info is carried forward into the NEW trailer', () {
    final result = out({0: layer});
    final lastTrailer = result.substring(result.lastIndexOf('trailer'));

    expect(lastTrailer, contains('/Info 7 0 R'));
  });

  group('the page dictionary', () {
    test('appends the OCR stream to /Contents, keeping the original', () {
      final result = out({0: layer});
      final page = RegExp(
        r'3 0 obj\n(<<.*?>>)\nendobj',
        dotAll: true,
      ).allMatches(result).last.group(1)!;

      expect(page, contains('/Contents [4 0 R'));
      expect(
        page,
        matches(RegExp(r'/Contents \[4 0 R \d+ 0 R\]')),
        reason: 'the scan must still be drawn',
      );
    });

    // Replacing /Resources would strip the page's own font and image, which
    // for a scanned page means losing the scan itself.
    test('merges the font into existing resources', () {
      final result = out({0: layer});
      final page = RegExp(
        r'3 0 obj\n(<<.*?>>)\nendobj',
        dotAll: true,
      ).allMatches(result).last.group(1)!;

      expect(page, contains('/OcF1'));
      expect(page, contains('/F1 9 0 R'), reason: 'the page font survives');
      expect(page, contains('/Im0 8 0 R'), reason: 'the page image survives');
      expect(
        RegExp(r'/Resources').allMatches(page).length,
        1,
        reason: 'one /Resources, not two - a reader takes only one',
      );
      expect(RegExp(r'/Font').allMatches(page).length, 1);
    });

    test('a page with no resources at all gets them', () {
      final result = out({1: layer});
      final page = RegExp(
        r'5 0 obj\n(<<.*?>>)\nendobj',
        dotAll: true,
      ).allMatches(result).last.group(1)!;

      expect(page, contains('/Resources'));
      expect(page, contains('/OcF1'));
      expect(page, contains('/Contents ['));
    });
  });

  test('one font object serves every page', () {
    final result = out({0: layer, 1: layer});

    expect(RegExp(r'/BaseFont /Helvetica').allMatches(result).length, 1);
  });

  test('a page with no layer is not rewritten', () {
    final result = out({0: layer});

    expect(
      RegExp(r'5 0 obj').allMatches(result).length,
      1,
      reason: 'page 5 appears only in the original bytes',
    );
  });

  group('refusals', () {
    test('no layers at all is refused', () {
      expect(() => writeOcrLayer(source(), const {}), throwsArgumentError);
    });

    // A page where OCR found nothing must not get an empty content stream and
    // a pointless rewrite.
    test('a blank layer counts as nothing', () {
      expect(() => writeOcrLayer(source(), {0: '   \n'}), throwsArgumentError);
    });

    test('a page index that does not exist is refused', () {
      expect(() => writeOcrLayer(source(), {9: layer}), throwsArgumentError);
    });
  });
}
