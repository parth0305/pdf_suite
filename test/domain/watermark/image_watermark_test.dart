import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/watermark/image_watermark_content.dart';
import 'package:folio/domain/watermark/pdf_image_watermark_writer.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// A 2x1 logo: opaque red, then fully transparent.
ImageWatermark markOf({double opacity = 0.5}) => ImageWatermark(
  rgba: const [255, 0, 0, 255, 0, 0, 255, 0],
  pixelWidth: 2,
  pixelHeight: 1,
  opacity: opacity,
);

Uint8List onePage() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 '
    '/MediaBox [0 0 400 800] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
    '/Resources << /XObject << /Own 9 0 R >> >> >>\nendobj\n'
    '4 0 obj\n<< /Length 9 >>\nstream\nPAGE-BODY\nendstream\nendobj\n'
    'xref\n0 5\n0000000000 65535 f \n'
    'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

void main() {
  group('samples', () {
    // Two sources of transparency: the picture's own alpha and the mark's
    // opacity. Using only the second paints the logo's background over the
    // page; using only the first ignores the opacity setting entirely.
    test('the image alpha and the opacity are multiplied', () {
      final samples = imageWatermarkSamples(markOf(opacity: 0.5));
      final alpha = ZLibCodec().decode(samples.alpha);

      expect(alpha[0], 128, reason: '255 opaque at half opacity');
      expect(alpha[1], 0, reason: 'already transparent stays transparent');
    });

    test('full opacity leaves the image alpha alone', () {
      final alpha = ZLibCodec().decode(
        imageWatermarkSamples(markOf(opacity: 1)).alpha,
      );

      expect(alpha[0], 255);
    });

    test('colour comes out as three channels, alpha as one', () {
      final samples = imageWatermarkSamples(markOf());

      expect(ZLibCodec().decode(samples.rgb), [255, 0, 0, 0, 0, 255]);
      expect(ZLibCodec().decode(samples.alpha), hasLength(2));
    });
  });

  group('the content stream', () {
    const box = TextRect(left: 0, right: 400, top: 800, bottom: 0);

    // An unbalanced graphics state corrupts everything drawn after it.
    test('q and Q are balanced', () {
      final stream = imageWatermarkContentStream(markOf(), mediaBox: box);

      expect(RegExp(r'\bq\b').allMatches(stream).length, 1);
      expect(RegExp(r'\bQ\b').allMatches(stream).length, 1);
    });

    // The opacity is already in the mask; a /ca here would apply it twice.
    test('no graphics state is set', () {
      expect(
        imageWatermarkContentStream(markOf(), mediaBox: box),
        isNot(contains(' gs')),
      );
    });

    test('the mark is scaled to the shorter side', () {
      final stream = imageWatermarkContentStream(
        ImageWatermark(
          rgba: markOf().rgba,
          pixelWidth: 2,
          pixelHeight: 1,
          scale: 0.5,
        ),
        mediaBox: box,
      );

      // Shorter side is 400, scale 0.5 gives 200 wide; aspect 2 gives 100 tall.
      expect(stream, contains('200 0 0 100'));
    });

    test('a horizontal mark is not rotated', () {
      final stream = imageWatermarkContentStream(
        ImageWatermark(
          rgba: markOf().rgba,
          pixelWidth: 2,
          pixelHeight: 1,
          rotation: WatermarkRotation.horizontal,
        ),
        mediaBox: box,
      );

      expect(RegExp(r'cm').allMatches(stream).length, 1);
    });

    test('a diagonal mark rotates about the page centre', () {
      final stream = imageWatermarkContentStream(markOf(), mediaBox: box);

      expect(stream, contains('200 400 cm'));
      expect(RegExp(r'cm').allMatches(stream).length, 2);
    });
  });

  group('writing', () {
    test('the original bytes are untouched', () {
      final original = onePage();
      final out = writeImageWatermark(original, markOf());

      expect(out.sublist(0, original.length), original);
    });

    test('one image and one mask serve the document', () {
      final out = latin1.decode(
        writeImageWatermark(onePage(), markOf()),
        allowInvalid: true,
      );

      expect(RegExp(r'/SMask').allMatches(out).length, 1);
      expect(RegExp(r'/ColorSpace /DeviceGray').allMatches(out).length, 1);
    });

    // The page's own image must survive; replacing /XObject would lose it.
    test('the page keeps its own resources', () {
      final out = latin1.decode(
        writeImageWatermark(onePage(), markOf()),
        allowInvalid: true,
      );
      final page = RegExp(
        r'3 0 obj(.*?)endobj',
        dotAll: true,
      ).allMatches(out).last.group(1)!;

      expect(page, contains('/Own 9 0 R'));
      expect(page, contains('/WMIm'));
      expect(RegExp(r'/XObject').allMatches(page).length, 1);
    });

    test('the page keeps its own drawing', () {
      final out = latin1.decode(
        writeImageWatermark(onePage(), markOf()),
        allowInvalid: true,
      );
      final page = RegExp(
        r'3 0 obj(.*?)endobj',
        dotAll: true,
      ).allMatches(out).last.group(1)!;

      expect(page, matches(RegExp(r'/Contents \[4 0 R \d+ 0 R\]')));
    });

    test('an empty or mis-sized image is refused', () {
      expect(
        () => writeImageWatermark(
          onePage(),
          const ImageWatermark(rgba: [1, 2], pixelWidth: 4, pixelHeight: 4),
        ),
        throwsArgumentError,
      );
    });
  });
}
