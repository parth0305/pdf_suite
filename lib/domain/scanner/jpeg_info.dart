import 'package:folio/core/errors/app_failure.dart';

/// What a PDF image dictionary needs to know about a JPEG.
class JpegInfo {
  const JpegInfo({
    required this.width,
    required this.height,
    required this.components,
  });

  final int width;
  final int height;

  /// 1 for grayscale, 3 for colour. Writing /DeviceRGB for a single-component
  /// JPEG produces a corrupt image, not a grey one.
  final int components;

  String get colorSpace => switch (components) {
    1 => '/DeviceGray',
    4 => '/DeviceCMYK',
    _ => '/DeviceRGB',
  };
}

/// Reads a JPEG's start-of-frame marker.
///
/// Only the frame header is parsed - never the entropy-coded data - because
/// the bytes are embedded in the PDF untouched. This exists to fill in the
/// image dictionary and to refuse what `/DCTDecode` cannot carry.
JpegInfo jpegInfo(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    throw const UnsupportedPdfStructure(technicalDetail: 'not a JPEG');
  }

  var i = 2;
  while (i + 3 < bytes.length) {
    // Markers may be preceded by any number of 0xFF fill bytes.
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    var marker = bytes[i + 1];
    var at = i + 1;
    while (marker == 0xFF && at + 1 < bytes.length) {
      at++;
      marker = bytes[at];
    }

    // Standalone markers carry no length: RSTn, SOI, EOI, TEM.
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i = at + 1;
      continue;
    }
    if (marker == 0xD9) break;

    if (at + 3 >= bytes.length) break;
    final length = (bytes[at + 1] << 8) | bytes[at + 2];
    if (length < 2) {
      throw const UnsupportedPdfStructure(
        technicalDetail: 'malformed JPEG segment length',
      );
    }

    // SOF0/1 are baseline and extended sequential; both are what DCTDecode
    // carries. SOF2 is progressive, SOF9/10 arithmetic-coded - a PDF holding
    // either renders as garbage in some readers and not at all in others, so
    // they are refused rather than written.
    if (marker == 0xC0 || marker == 0xC1) {
      if (at + 8 >= bytes.length) break;
      return JpegInfo(
        height: (bytes[at + 4] << 8) | bytes[at + 5],
        width: (bytes[at + 6] << 8) | bytes[at + 7],
        components: bytes[at + 8],
      );
    }
    if (marker == 0xC2 ||
        marker == 0xC3 ||
        (marker >= 0xC9 && marker <= 0xCB)) {
      throw const UnsupportedPdfStructure(
        technicalDetail: 'progressive or arithmetic-coded JPEG',
      );
    }

    // Once the scan starts there is no frame header left to find.
    if (marker == 0xDA) break;

    i = at + 1 + length;
  }

  throw const UnsupportedPdfStructure(
    technicalDetail: 'no JPEG start-of-frame marker',
  );
}
