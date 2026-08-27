import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/image_appearance.dart';
import 'package:folio/domain/engine/pdf_types.dart';

ImageAnnotation annotationOf(List<int> rgba, {int w = 2, int h = 2}) =>
    ImageAnnotation(
      pageIndex: 0,
      rect: const TextRect(left: 10, top: 60, right: 110, bottom: 10),
      rgba: rgba,
      pixelWidth: w,
      pixelHeight: h,
    );

/// Two opaque red pixels then two transparent ones.
final sample = <int>[255, 0, 0, 255, 255, 0, 0, 255, 9, 9, 9, 0, 9, 9, 9, 0];

void main() {
  group('splitting colour from transparency', () {
    // PDF has no RGBA image. Interleaved alpha in the colour stream would be
    // read as a fourth colour channel and render as noise.
    test('colour and alpha come out as separate streams', () {
      final parts = imageAppearanceParts(annotationOf(sample));

      expect(ZLibCodec().decode(parts.rgb), [
        255,
        0,
        0,
        255,
        0,
        0,
        9,
        9,
        9,
        9,
        9,
        9,
      ]);
      expect(ZLibCodec().decode(parts.alpha), [255, 255, 0, 0]);
    });

    test('the mask has one channel per pixel, not four', () {
      final parts = imageAppearanceParts(annotationOf(sample));

      expect(ZLibCodec().decode(parts.alpha), hasLength(4));
      expect(ZLibCodec().decode(parts.rgb), hasLength(12));
    });

    test('a wrongly sized buffer is refused', () {
      expect(
        () => imageAppearanceParts(annotationOf(const [1, 2, 3], w: 4, h: 4)),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('expected'),
          ),
        ),
      );
    });
  });

  group('the dictionaries', () {
    test('the image names its mask', () {
      final parts = imageAppearanceParts(annotationOf(sample));

      expect(imageXObjectDict(parts, 7), contains('/SMask 7 0 R'));
      expect(imageXObjectDict(parts, 7), contains('/ColorSpace /DeviceRGB'));
    });

    // A mask declared /DeviceRGB is read as three channels and the
    // transparency comes out as stripes.
    test('the mask is greyscale', () {
      final parts = imageAppearanceParts(annotationOf(sample));

      expect(maskXObjectDict(parts), contains('/ColorSpace /DeviceGray'));
      expect(maskXObjectDict(parts), isNot(contains('/SMask')));
    });

    test('both declare their compressed lengths', () {
      final parts = imageAppearanceParts(annotationOf(sample));

      expect(
        imageXObjectDict(parts, 7),
        contains('/Length ${parts.rgb.length}'),
      );
      expect(maskXObjectDict(parts), contains('/Length ${parts.alpha.length}'));
    });

    test('the mask matches the image dimensions', () {
      final parts = imageAppearanceParts(annotationOf(sample));

      for (final dict in [imageXObjectDict(parts, 7), maskXObjectDict(parts)]) {
        expect(dict, contains('/Width 2'));
        expect(dict, contains('/Height 2'));
      }
    });
  });

  group('the appearance stream', () {
    test('draws the image across the whole BBox', () {
      final annotation = annotationOf(sample);
      final parts = imageAppearanceParts(annotation);

      // The rect is 100 wide and 50 tall.
      expect(parts.content, contains('100 0 0 50 0 0 cm'));
      expect(parts.content, contains('/SigIm Do'));
    });

    test('the BBox starts at the origin, not at the page position', () {
      final annotation = annotationOf(sample);
      final parts = imageAppearanceParts(annotation);
      final dict = imageAppearanceDict(annotation, parts, 40, '', 7);

      // The annotation sits at x=10 on the page, but its appearance space
      // starts at zero: /Rect is what places it.
      expect(dict, contains('/BBox [0 0 100 50]'));
      expect(dict, contains('/XObject << /SigIm 7 0 R >>'));
    });
  });
}
