import 'dart:io';
import 'dart:math' as math;

import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// The image watermark's colour samples and its transparency mask.
///
/// Alpha comes from two places and both matter: the picture's own transparency
/// (a logo on a transparent background) multiplied by the mark's opacity. Using
/// only the second would paint the logo's own background over the page.
({List<int> rgb, List<int> alpha}) imageWatermarkSamples(ImageWatermark mark) {
  final pixels = mark.pixelWidth * mark.pixelHeight;
  final rgb = List<int>.filled(pixels * 3, 0);
  final alpha = List<int>.filled(pixels, 0);

  for (var p = 0; p < pixels; p++) {
    rgb[p * 3] = mark.rgba[p * 4];
    rgb[p * 3 + 1] = mark.rgba[p * 4 + 1];
    rgb[p * 3 + 2] = mark.rgba[p * 4 + 2];
    alpha[p] = (mark.rgba[p * 4 + 3] * mark.opacity).round().clamp(0, 255);
  }

  return (
    rgb: ZLibCodec(level: 6).encode(rgb),
    alpha: ZLibCodec(level: 6).encode(alpha),
  );
}

/// The content stream that draws [mark] centred on a page of [mediaBox].
///
/// Balanced q/Q, like the text watermark: an unbalanced graphics state
/// corrupts everything drawn after it on the page.
String imageWatermarkContentStream(
  ImageWatermark mark, {
  required TextRect mediaBox,
}) {
  final shorter = math.min(mediaBox.width, mediaBox.height);
  final width = shorter * mark.scale;
  final height = width / mark.aspectRatio;

  final cx = mediaBox.left + mediaBox.width / 2;
  final cy = mediaBox.bottom + mediaBox.height / 2;

  // No ExtGState: the mark's opacity is already multiplied into the soft
  // mask, so a /ca here would apply it twice.
  final buffer = StringBuffer('q\n');

  if (mark.rotation == WatermarkRotation.diagonal) {
    // Rotate about the page centre, then draw the image centred on the
    // origin - the same order the text mark uses.
    const radians = 45 * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    buffer.writeln(
      '${pdfNumber(cos)} ${pdfNumber(sin)} ${pdfNumber(-sin)} '
      '${pdfNumber(cos)} ${pdfNumber(cx)} ${pdfNumber(cy)} cm',
    );
    buffer.writeln(
      '${pdfNumber(width)} 0 0 ${pdfNumber(height)} '
      '${pdfNumber(-width / 2)} ${pdfNumber(-height / 2)} cm',
    );
  } else {
    buffer.writeln(
      '${pdfNumber(width)} 0 0 ${pdfNumber(height)} '
      '${pdfNumber(cx - width / 2)} ${pdfNumber(cy - height / 2)} cm',
    );
  }

  buffer
    ..writeln('/WMIm Do')
    ..writeln('Q');

  return buffer.toString();
}
