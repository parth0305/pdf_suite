import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/scanner/jpeg_info.dart';

import 'jpeg_fixtures.dart';

/// A JPEG header with the given start-of-frame marker and component count.
///
/// Synthetic because `sips` will not emit a progressive JPEG, and the parser
/// reads only headers - it never touches entropy-coded data - so a header is
/// the whole of what it sees.
List<int> synthetic({
  required int sofMarker,
  int components = 3,
  int width = 100,
  int height = 200,
  bool withApp1 = true,
}) => [
  0xFF, 0xD8,
  // The APP1 payload deliberately CONTAINS what looks like a start-of-frame
  // marker with different dimensions. A parser that scans byte by byte instead
  // of skipping each segment by its declared length reads this decoy and
  // reports 1x1. Without those bytes the test cannot tell the two apart.
  if (withApp1) ...[
    0xFF,
    0xE1,
    0x00,
    0x0D,
    0xFF,
    0xC0,
    0x00,
    0x0B,
    8,
    0,
    1,
    0,
    1,
    1,
    1,
    0x11,
    0,
  ],
  0xFF, sofMarker,
  0x00, 8 + components * 3,
  8, // sample precision
  (height >> 8) & 0xFF, height & 0xFF,
  (width >> 8) & 0xFF, width & 0xFF,
  components,
  for (var c = 0; c < components; c++) ...[c + 1, 0x11, 0],
  0xFF, 0xDA,
];

void main() {
  group('real JPEGs', () {
    test('a colour baseline JPEG reports its size and three components', () {
      final info = jpegInfo(kColourJpeg);

      expect(info.width, 64);
      expect(info.height, 64);
      expect(info.components, 3);
      expect(info.colorSpace, '/DeviceRGB');
    });

    // /DeviceRGB on a single-component JPEG produces a corrupt image, not a
    // grey one: the reader expects three samples per pixel and finds one.
    test('a grayscale JPEG reports one component and DeviceGray', () {
      final info = jpegInfo(kGrayJpeg);

      expect(info.components, 1);
      expect(info.colorSpace, '/DeviceGray');
    });
  });

  group('frame headers', () {
    test('reads width and height the right way round', () {
      // JPEG stores height BEFORE width. Swapping them is invisible on a
      // square image, which is why this one is not square.
      final info = jpegInfo(
        synthetic(sofMarker: 0xC0, width: 100, height: 200),
      );

      expect(info.width, 100);
      expect(info.height, 200);
    });

    test('extended sequential (SOF1) is accepted', () {
      expect(jpegInfo(synthetic(sofMarker: 0xC1)).width, 100);
    });

    test('a CMYK JPEG reports DeviceCMYK', () {
      expect(
        jpegInfo(synthetic(sofMarker: 0xC0, components: 4)).colorSpace,
        '/DeviceCMYK',
      );
    });

    test('segments before the frame are skipped by their length', () {
      final info = jpegInfo(synthetic(sofMarker: 0xC0));

      expect(info.width, 100);
      expect(info.height, 200, reason: 'the decoy frame inside APP1 says 1x1');
    });
  });

  group('refusals', () {
    // DCTDecode carries baseline JPEG. A progressive one renders as garbage in
    // some readers and not at all in others.
    //
    // The DETAIL is asserted, not just the type. Without the progressive check
    // the parser skips SOF2 as an unknown segment and throws 'no start-of-frame
    // marker' - the same exception class, so a type-only assertion cannot tell
    // a correct refusal from a misleading one, and the user is told their photo
    // is not a JPEG when in fact it is the wrong kind of JPEG.
    test('progressive (SOF2) is refused, and says why', () {
      expect(
        () => jpegInfo(synthetic(sofMarker: 0xC2)),
        throwsA(
          isA<UnsupportedPdfStructure>().having(
            (e) => e.technicalDetail,
            'technicalDetail',
            contains('progressive'),
          ),
        ),
      );
    });

    test('arithmetic-coded (SOF9) is refused, and says why', () {
      expect(
        () => jpegInfo(synthetic(sofMarker: 0xC9)),
        throwsA(
          isA<UnsupportedPdfStructure>().having(
            (e) => e.technicalDetail,
            'technicalDetail',
            contains('arithmetic'),
          ),
        ),
      );
    });

    test('something that is not a JPEG is refused', () {
      expect(
        () => jpegInfo(const [0x89, 0x50, 0x4E, 0x47]),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });

    test('a truncated JPEG is refused rather than returning nonsense', () {
      expect(
        () => jpegInfo(kColourJpeg.sublist(0, 10)),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });

    test('a JPEG with no frame at all is refused', () {
      expect(
        () => jpegInfo(const [0xFF, 0xD8, 0xFF, 0xD9]),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });
  });
}
