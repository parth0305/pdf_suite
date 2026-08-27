import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/redaction/redaction_box.dart';

/// Pixels per inch a redacted page is rasterised at.
///
/// At 200 DPI an A4 page is 1654x2339, whose raw RGB samples are 11.6 MB and
/// deflate to a few hundred kilobytes for typical text. 300 DPI more than
/// doubles that for a difference few readers would notice on a page that has
/// already become an image.
const redactionDpi = 200;

/// The pixel size a page of [mediaBox] points rasterises to at [redactionDpi].
({int width, int height}) rasterSizeFor(TextRect mediaBox) => (
  width: (mediaBox.width * redactionDpi / 72).round(),
  height: (mediaBox.height * redactionDpi / 72).round(),
);

/// Paints every box on [pageIndex] solid black into a copy of [bgra].
///
/// PDF's origin is bottom-left and a raster's is top-left, so the vertical
/// axis is flipped. Forgetting that redacts the mirror image of what the user
/// selected, which still looks like a successful redaction.
List<int> paintBoxes({
  required List<int> bgra,
  required int widthPx,
  required int heightPx,
  required TextRect mediaBox,
  required List<RedactionBox> boxes,
  required int pageIndex,
}) {
  final out = List<int>.of(bgra);
  final scaleX = widthPx / mediaBox.width;
  final scaleY = heightPx / mediaBox.height;

  for (final box in boxes.where((b) => b.pageIndex == pageIndex)) {
    final r = box.rect;
    final left = ((r.left - mediaBox.left) * scaleX).floor().clamp(0, widthPx);
    final right = ((r.right - mediaBox.left) * scaleX).ceil().clamp(0, widthPx);
    // The flip: a box's TOP in PDF points is the SMALLER raster row.
    final top = ((mediaBox.top - r.top) * scaleY).floor().clamp(0, heightPx);
    final bottom = ((mediaBox.top - r.bottom) * scaleY).ceil().clamp(
      0,
      heightPx,
    );

    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final i = (y * widthPx + x) * 4;
        out[i] = 0;
        out[i + 1] = 0;
        out[i + 2] = 0;
        out[i + 3] = 255;
      }
    }
  }

  return out;
}

/// Converts PDFium's BGRA output to the RGB samples a PDF image XObject wants.
///
/// Getting the order wrong swaps red and blue on every redacted page, which
/// looks deliberate rather than broken.
List<int> bgraToRgb(List<int> bgra) {
  final rgb = List<int>.filled(bgra.length ~/ 4 * 3, 0);

  for (var p = 0; p < bgra.length ~/ 4; p++) {
    rgb[p * 3] = bgra[p * 4 + 2];
    rgb[p * 3 + 1] = bgra[p * 4 + 1];
    rgb[p * 3 + 2] = bgra[p * 4];
  }

  return rgb;
}
