import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/redaction/pdf_image_object.dart';
import 'package:folio/domain/redaction/redaction_raster.dart';
import 'package:folio/domain/redaction/redaction_box.dart';

/// A 4x4 buffer of one colour, in BGRA as PDFium produces it.
List<int> solid(int b, int g, int r) => [
  for (var i = 0; i < 16; i++) ...[b, g, r, 255],
];

const page = TextRect(left: 0, right: 40, top: 40, bottom: 0);

void main() {
  group('bgraToRgb', () {
    // PDFium hands back BGRA; a PDF image XObject wants RGB. Getting the
    // order wrong swaps red and blue in every redacted page, which looks
    // deliberate rather than broken.
    test('reorders the channels and drops alpha', () {
      // One pure-red BGRA pixel: blue 0, green 0, red 255.
      expect(bgraToRgb(const [0, 0, 255, 255]), [255, 0, 0]);
    });

    test('a pure blue pixel does not come back red', () {
      expect(bgraToRgb(const [255, 0, 0, 255]), [0, 0, 255]);
    });

    test('the output is three bytes per pixel', () {
      expect(bgraToRgb(solid(1, 2, 3)), hasLength(16 * 3));
    });
  });

  group('paintBoxes', () {
    List<int> painted(RedactionBox box) => paintBoxes(
      bgra: solid(255, 255, 255),
      widthPx: 4,
      heightPx: 4,
      mediaBox: page,
      boxes: [box],
      pageIndex: 0,
    );

    ({int b, int g, int r}) pixel(List<int> bgra, int x, int y) {
      final i = (y * 4 + x) * 4;
      return (b: bgra[i], g: bgra[i + 1], r: bgra[i + 2]);
    }

    test('every pixel under a box is black', () {
      // Covers the whole page.
      final out = painted(const RedactionBox(pageIndex: 0, rect: page));

      expect(pixel(out, 0, 0), (b: 0, g: 0, r: 0));
      expect(pixel(out, 3, 3), (b: 0, g: 0, r: 0));
    });

    test('a pixel outside the box is untouched', () {
      // Left half only: PDF x 0..20 of a 40-wide page.
      final out = painted(
        const RedactionBox(
          pageIndex: 0,
          rect: TextRect(left: 0, right: 20, top: 40, bottom: 0),
        ),
      );

      expect(pixel(out, 0, 0), (b: 0, g: 0, r: 0));
      expect(pixel(out, 3, 0), (b: 255, g: 255, r: 255));
    });

    // PDF's origin is bottom-left; a raster's is top-left. Forgetting the flip
    // redacts the mirror image of what the user selected - which still LOOKS
    // like a redaction.
    test('the vertical axis is flipped', () {
      // The TOP quarter of the page in PDF points: y 30..40.
      final out = painted(
        const RedactionBox(
          pageIndex: 0,
          rect: TextRect(left: 0, right: 40, top: 40, bottom: 30),
        ),
      );

      expect(pixel(out, 0, 0), (
        b: 0,
        g: 0,
        r: 0,
      ), reason: 'PDF top maps to raster row 0');
      expect(pixel(out, 0, 3), (
        b: 255,
        g: 255,
        r: 255,
      ), reason: 'PDF bottom maps to the last raster row');
    });

    test('a box on another page paints nothing', () {
      final out = paintBoxes(
        bgra: solid(255, 255, 255),
        widthPx: 4,
        heightPx: 4,
        mediaBox: page,
        boxes: [const RedactionBox(pageIndex: 1, rect: page)],
        pageIndex: 0,
      );

      expect(pixel(out, 0, 0), (b: 255, g: 255, r: 255));
    });

    test('the input buffer is not mutated', () {
      final input = solid(255, 255, 255);
      paintBoxes(
        bgra: input,
        widthPx: 4,
        heightPx: 4,
        mediaBox: page,
        boxes: [const RedactionBox(pageIndex: 0, rect: page)],
        pageIndex: 0,
      );

      expect(input.first, 255, reason: 'callers keep their own pixels');
    });
  });

  group('imageXObject', () {
    test('declares the compressed length and the pixel dimensions', () {
      final rgb = List<int>.filled(4 * 4 * 3, 200);
      final image = imageXObject(widthPx: 4, heightPx: 4, rgb: rgb);

      expect(image.dict, contains('/Width 4'));
      expect(image.dict, contains('/Height 4'));
      expect(image.dict, contains('/Length ${image.samples.length}'));
      expect(image.dict, contains('/FlateDecode'));
    });

    test('the samples inflate back to the pixels given', () {
      final rgb = [for (var i = 0; i < 48; i++) i * 5 % 256];
      final image = imageXObject(widthPx: 4, heightPx: 4, rgb: rgb);

      expect(ZLibCodec().decode(image.samples), rgb);
    });

    // A /Length describing the uncompressed samples is a stream no reader can
    // parse - the same failure the watermark compression work found.
    test('the declared length is the compressed one, not the raw one', () {
      final rgb = List<int>.filled(4 * 4 * 3, 200);
      final image = imageXObject(widthPx: 4, heightPx: 4, rgb: rgb);

      expect(image.samples.length, lessThan(rgb.length));
      expect(image.dict, isNot(contains('/Length ${rgb.length}')));
    });

    test('a mismatched sample count is refused', () {
      expect(
        () => imageXObject(widthPx: 4, heightPx: 4, rgb: const [1, 2, 3]),
        throwsArgumentError,
      );
    });
  });
}
