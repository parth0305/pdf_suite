import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/compression/compression_estimate.dart';
import 'package:folio/domain/compression/pdf_compressor.dart';

/// Objects 4 and 6 are byte-identical fonts, which is what merging two
/// documents produces. Object 7 is referenced by nobody. Object 8 has an
/// uncompressed stream worth deflating.
final longFont =
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
    '/Encoding /WinAnsiEncoding /FirstChar 32 /LastChar 255 '
    '/Widths [${List.filled(60, '500').join(' ')}] >>';

final repetitive = List.filled(80, 'q 1 0 0 RG 10 10 m 20 20 l S Q').join('\n');

/// Deliberately contains the text `6 0 R`. Object 6 is the duplicate that
/// dedupe remaps to 4, so anything that rewrites references inside a stream
/// payload will corrupt this - which is exactly what an image's bytes would
/// suffer.
const bytesLikeARef = 'BINARY-6 0 R-DATA';

Uint8List source() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 8 0 R '
    '/Resources << /Font << /F1 4 0 R >> /XObject << /Im0 9 0 R >> >> >>\nendobj\n'
    '4 0 obj\n$longFont\nendobj\n'
    '5 0 obj\n<< /Type /Page /Parent 2 0 R '
    '/Resources << /Font << /F1 6 0 R >> >> >>\nendobj\n'
    '6 0 obj\n$longFont\nendobj\n'
    '7 0 obj\n<< /Type /Unused /Padding (${'x' * 200}) >>\nendobj\n'
    '8 0 obj\n<< /Length ${repetitive.length} >>\nstream\n'
    '$repetitive\nendstream\nendobj\n'
    '9 0 obj\n<< /Length ${bytesLikeARef.length} /Filter /DCTDecode >>\n'
    'stream\n$bytesLikeARef\nendstream\nendobj\n'
    'xref\n0 10\n0000000000 65535 f \n'
    'trailer\n<< /Size 10 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

String out() => latin1.decode(compressPdf(source()).bytes, allowInvalid: true);

void main() {
  group('the breakdown', () {
    test('attributes the duplicate font', () {
      expect(compressPdf(source()).duplicateBytes, greaterThan(200));
    });

    test('attributes the object nothing references', () {
      expect(compressPdf(source()).orphanedBytes, greaterThan(200));
    });

    test('attributes what deflating the content stream saves', () {
      expect(compressPdf(source()).deflatableBytes, greaterThan(100));
    });

    // The number shown to the user is the real difference in bytes, not a
    // prediction. A per-object estimate cannot model the rewrite's own
    // overhead, and it over-promised by 215 bytes when it tried.
    test('the saving is exactly the difference in file size', () {
      final result = compressPdf(source());

      expect(result.savedBytes, source().length - result.bytes.length);
    });

    test('the breakdown does not have to sum to the saving', () {
      final result = compressPdf(source());
      final parts =
          result.duplicateBytes + result.orphanedBytes + result.deflatableBytes;

      // It explains where the saving came from; the rewrite's own overhead is
      // why the two differ.
      expect(parts, greaterThan(0));
      expect(result.savedBytes, greaterThan(0));
    });
  });

  group('worthDoing', () {
    CompressionResult resultOf({
      required int original,
      required int compressed,
    }) => CompressionResult(
      bytes: Uint8List(compressed),
      originalBytes: original,
      duplicateBytes: 0,
      orphanedBytes: 0,
      deflatableBytes: 0,
    );

    test('a small fraction of a large file still counts', () {
      final result = resultOf(
        original: 20 * 1024 * 1024,
        compressed: 20 * 1024 * 1024 - 60 * 1024,
      );

      expect(result.savedFraction, lessThan(0.02));
      expect(result.worthDoing, isTrue, reason: '60KB is worth having');
    });

    test('a large fraction of a small file counts', () {
      final result = resultOf(original: 60 * 1024, compressed: 20 * 1024);

      expect(result.savedBytes, lessThan(50 * 1024));
      expect(result.worthDoing, isTrue);
    });

    // Measured: a 3.6MB passport scan yielded 632 bytes. Offering to compress
    // that is offering nothing.
    test('an already-compressed document is not worth it', () {
      final result = resultOf(
        original: 3 * 1024 * 1024,
        compressed: 3 * 1024 * 1024 - 632,
      );

      expect(result.worthDoing, isFalse);
    });

    test('a document that would GROW is never worth it', () {
      final result = resultOf(original: 1000, compressed: 1200);

      expect(result.savedBytes, lessThan(0));
      expect(result.worthDoing, isFalse);
    });
  });

  group('compressPdf', () {
    test('collapses the duplicate font to one object', () {
      final result = out();

      expect(
        RegExp(r'/BaseFont /Helvetica').allMatches(result).length,
        1,
        reason: 'the second copy is gone',
      );
    });

    // Both pages must still HAVE a font. Collapsing the object without
    // repointing the reference leaves page 2 pointing at nothing.
    test('the page that used the duplicate now points at the survivor', () {
      final result = out();

      final page5 = RegExp(
        r'5 0 obj(.*?)endobj',
        dotAll: true,
      ).firstMatch(result)!.group(1)!;

      expect(page5, contains('/F1 4 0 R'));
      expect(page5, isNot(contains('/F1 6 0 R')));
    });

    test('drops the unreferenced object', () {
      expect(out(), isNot(contains('/Type /Unused')));
    });

    test('deflates the uncompressed stream', () {
      final result = out();

      expect(result, contains('/FlateDecode'));
      expect(
        result,
        isNot(contains('q 1 0 0 RG 10 10 m 20 20 l S Q')),
        reason: 'a deflated stream is not readable in the raw bytes',
      );
    });

    test('the result is smaller', () {
      expect(compressPdf(source()).bytes.length, lessThan(source().length));
    });

    test('every page survives', () {
      expect(RegExp(r'/Type /Page\b').allMatches(out()).length, 2);
    });

    test('the catalog and page tree survive', () {
      final result = out();

      expect(result, contains('/Type /Catalog'));
      expect(result, contains('/Type /Pages'));
      expect(result, contains('/Root 1 0 R'));
    });
  });

  group('what must never be touched', () {
    // An already-compressed stream's bytes are arbitrary. Bytes that happen to
    // read as `6 0 R` are image data, not a reference, and remapping them
    // corrupts the image while leaving the file structurally valid.
    test('bytes inside a stream that look like a reference survive', () {
      expect(out(), contains(bytesLikeARef));
      expect(
        out(),
        isNot(contains('BINARY-4 0 R-DATA')),
        reason: 'the payload must not be remapped',
      );
    });

    test('an already-filtered stream is left alone', () {
      expect(out(), contains('/Filter /DCTDecode'));
    });

    // A /Length that describes the text the bytes came from rather than the
    // bytes written is a stream no reader can parse: it reads past the end or
    // stops short.
    test('a deflated stream declares its compressed length', () {
      final result = out();
      final match = RegExp(
        r'/Length (\d+) /Filter /FlateDecode >>\s*stream\n',
      ).firstMatch(result)!;

      final declared = int.parse(match.group(1)!);
      final endstream = result.indexOf('endstream', match.end);

      expect(
        declared,
        lessThan(repetitive.length),
        reason: 'it must be the compressed size, not the original',
      );
      expect(
        endstream - match.end,
        declared + 1,
        reason: 'the declared length must reach exactly to endstream',
      );
    });
  });
}
