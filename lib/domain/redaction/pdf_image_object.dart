import 'dart:io';

/// An image XObject's dictionary and the compressed samples that follow it.
///
/// Raw RGB under /FlateDecode, which needs no image encoder and no dependency.
/// A device probe confirmed PDFium renders exactly this shape on iOS and
/// Android before any of the redaction pipeline was built.
({String dict, List<int> samples}) imageXObject({
  required int widthPx,
  required int heightPx,
  required List<int> rgb,
}) {
  final expected = widthPx * heightPx * 3;
  if (rgb.length != expected) {
    throw ArgumentError.value(
      rgb.length,
      'rgb',
      'expected $expected samples for ${widthPx}x$heightPx RGB',
    );
  }

  final samples = ZLibCodec(level: 6).encode(rgb);

  return (
    // /Length describes the COMPRESSED bytes. Declaring the raw count is the
    // classic way to write a stream no reader can parse.
    dict:
        '<< /Type /XObject /Subtype /Image '
        '/Width $widthPx /Height $heightPx '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 '
        '/Length ${samples.length} /Filter /FlateDecode >>',
    samples: samples,
  );
}
