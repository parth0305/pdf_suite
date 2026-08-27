import 'dart:io';

import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';

/// The bytes of an image appearance: the picture, its transparency mask, and
/// the content stream that draws it.
class ImageAppearanceParts {
  const ImageAppearanceParts({
    required this.rgb,
    required this.alpha,
    required this.content,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  /// Deflated RGB samples, alpha stripped out.
  final List<int> rgb;

  /// Deflated single-channel alpha, which becomes the /SMask.
  final List<int> alpha;

  /// The appearance stream, which just draws the image across the /BBox.
  final String content;

  final int pixelWidth;
  final int pixelHeight;
}

/// Splits an RGBA image into what a PDF needs: colour and mask, separately.
///
/// PDF has no RGBA image. Transparency is a second, greyscale image referenced
/// as /SMask, and the two must have the same dimensions. Interleaved alpha in
/// the colour stream would be read as a fourth colour channel and render as
/// noise.
ImageAppearanceParts imageAppearanceParts(ImageAnnotation annotation) {
  final pixels = annotation.pixelWidth * annotation.pixelHeight;
  if (annotation.rgba.length != pixels * 4) {
    throw ArgumentError.value(
      annotation.rgba.length,
      'rgba',
      'expected ${pixels * 4} bytes for '
          '${annotation.pixelWidth}x${annotation.pixelHeight}',
    );
  }

  final rgb = List<int>.filled(pixels * 3, 0);
  final alpha = List<int>.filled(pixels, 0);

  for (var p = 0; p < pixels; p++) {
    rgb[p * 3] = annotation.rgba[p * 4];
    rgb[p * 3 + 1] = annotation.rgba[p * 4 + 1];
    rgb[p * 3 + 2] = annotation.rgba[p * 4 + 2];
    alpha[p] = annotation.rgba[p * 4 + 3];
  }

  final w = annotation.rect.width;
  final h = annotation.rect.height;

  return ImageAppearanceParts(
    rgb: ZLibCodec(level: 6).encode(rgb),
    alpha: ZLibCodec(level: 6).encode(alpha),
    // The appearance's own space starts at the origin, so the image is drawn
    // at 0,0 and the annotation's /Rect places it on the page.
    content: 'q\n${pdfNumber(w)} 0 0 ${pdfNumber(h)} 0 0 cm\n/SigIm Do\nQ\n',
    pixelWidth: annotation.pixelWidth,
    pixelHeight: annotation.pixelHeight,
  );
}

/// The image XObject dictionary, naming its mask.
String imageXObjectDict(ImageAppearanceParts parts, int maskNumber) =>
    '<< /Type /XObject /Subtype /Image '
    '/Width ${parts.pixelWidth} /Height ${parts.pixelHeight} '
    '/ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask $maskNumber 0 R '
    '/Length ${parts.rgb.length} /Filter /FlateDecode >>';

/// The mask: one greyscale channel, the same size as the image it masks.
String maskXObjectDict(ImageAppearanceParts parts) =>
    '<< /Type /XObject /Subtype /Image '
    '/Width ${parts.pixelWidth} /Height ${parts.pixelHeight} '
    '/ColorSpace /DeviceGray /BitsPerComponent 8 '
    '/Length ${parts.alpha.length} /Filter /FlateDecode >>';

/// The appearance stream's dictionary, holding the image in its /Resources.
String imageAppearanceDict(
  ImageAnnotation annotation,
  ImageAppearanceParts parts,
  int length,
  String filter,
  int imageNumber,
) =>
    '<< /Type /XObject /Subtype /Form '
    '/BBox [0 0 ${pdfNumber(annotation.rect.width)} '
    '${pdfNumber(annotation.rect.height)}] '
    '/Resources << /XObject << /SigIm $imageNumber 0 R >> >> '
    '/Length $length$filter >>';
