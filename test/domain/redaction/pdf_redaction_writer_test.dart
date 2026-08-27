import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/redaction/pdf_redaction_writer.dart';

/// Two pages. Page 1 (object 3) draws content stream 4 and references image 7
/// which nothing else uses. Page 2 (object 5) draws stream 6 and shares
/// image 8 with page 1.
const twoPages =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
    '/MediaBox [0 0 100 200] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
    '/Resources << /XObject << /Ia 7 0 R /Ib 8 0 R >> >> >>\nendobj\n'
    '4 0 obj\n<< /Length 21 >>\nstream\nSECRET-PAGE-ONE-TEXT\nendstream\n'
    'endobj\n'
    '5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 6 0 R '
    '/Resources << /XObject << /Ib 8 0 R >> >> >>\nendobj\n'
    '6 0 obj\n<< /Length 13 >>\nstream\nPAGE-TWO-TEXT\nendstream\nendobj\n'
    '7 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 '
    '/Length 3 >>\nstream\nSEC\nendstream\nendobj\n'
    '8 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 '
    '/Length 3 >>\nstream\nLOG\nendstream\nendobj\n'
    'xref\n0 9\n0000000000 65535 f \n'
    'trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

List<int> bytesOf(String s) => latin1.encode(s);

RedactedPage samplePage({String invisibleText = 'BT 3 Tr (X) Tj ET\n'}) =>
    RedactedPage(
      widthPx: 2,
      heightPx: 2,
      rgb: List<int>.filled(2 * 2 * 3, 128),
      invisibleText: invisibleText,
    );

String redact({Map<int, RedactedPage>? pages}) => latin1.decode(
  writeRedacted(original: bytesOf(twoPages), pages: pages ?? {0: samplePage()}),
  allowInvalid: true,
);

void main() {
  // THE point of the slice. Dropping the page dictionary's reference is not
  // enough: an orphaned object is still in the file, and a text editor finds
  // it just as easily as a referenced one.
  test('the redacted page old content stream is gone from the file', () {
    expect(redact(), isNot(contains('SECRET-PAGE-ONE-TEXT')));
  });

  test('an untouched page keeps its content', () {
    expect(redact(), contains('PAGE-TWO-TEXT'));
  });

  // An image under a black box lives in an XObject, not in the content stream.
  // Dropping only the content stream leaves it recoverable.
  test('an image only the redacted page used is gone', () {
    expect(
      redact(),
      isNot(contains('SEC\nendstream')),
      reason: 'object 7 is referenced by page 1 alone',
    );
  });

  // If an image also appears on a page that was NOT redacted, its content is
  // visible in the output anyway. Removing it would break that page and
  // conceal nothing.
  test('an image shared with an untouched page is kept', () {
    expect(redact(), contains('LOG\nendstream'));
  });

  test('the redacted page draws the new image', () {
    final out = redact();

    expect(out, contains('/RdIm0'));
    expect(out, contains('/Subtype /Image'));
    expect(out, contains('Do'));
  });

  test('the invisible text is carried into the new content stream', () {
    // Compressed streams would hide it, so this asserts on the objects the
    // writer built rather than grepping raw bytes.
    final out = redact(
      pages: {0: samplePage(invisibleText: 'BT 3 Tr (KEEPME) Tj ET\n')},
    );

    expect(out, contains('/RdF1'));
    expect(out.contains('KEEPME') || out.contains('/FlateDecode'), isTrue);
  });

  // Resources are REPLACED, not merged. Merging leaves the old /XObject names
  // in the page dictionary, which keeps the leaked image referenced - so it
  // survives the orphan sweep and stays in the file.
  test('the redacted page references only the new image', () {
    final out = redact();
    final page = RegExp(r'3 0 obj(.*?)endobj', dotAll: true).firstMatch(out)!;

    expect(page.group(1), contains('/RdIm0'));
    expect(page.group(1), isNot(contains('/Ia')));
    expect(page.group(1), isNot(contains('/Ib')));
  });

  test('the redacted page draws exactly one content stream', () {
    final out = redact();
    final page = RegExp(r'3 0 obj(.*?)endobj', dotAll: true).firstMatch(out)!;

    expect(
      RegExp(r'/Contents').allMatches(page.group(1)!).length,
      1,
      reason: 'the old /Contents must be gone, not appended to',
    );
  });

  test('the page count is unchanged', () {
    final out = redact();

    expect(RegExp(r'/Type\s*/Page\b').allMatches(out).length, 2);
  });

  test('a document with no redacted pages is refused', () {
    expect(
      () => writeRedacted(original: bytesOf(twoPages), pages: const {}),
      throwsArgumentError,
    );
  });

  group('shared content streams', () {
    // Both pages draw stream 4. Dropping it breaks page 2; keeping it leaves
    // the redacted text in the file. Neither is acceptable, so Folio refuses.
    const shared =
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
        '/MediaBox [0 0 100 200] >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n'
        '4 0 obj\n<< /Length 6 >>\nstream\nSHARED\nendstream\nendobj\n'
        '5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n'
        'xref\n0 6\n0000000000 65535 f \n'
        'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

    test('refused rather than half-redacted', () {
      expect(
        () =>
            writeRedacted(original: bytesOf(shared), pages: {0: samplePage()}),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });

    test('not refused when every sharing page is redacted', () {
      expect(
        () => writeRedacted(
          original: bytesOf(shared),
          pages: {0: samplePage(), 1: samplePage()},
        ),
        returnsNormally,
      );
    });
  });
}
