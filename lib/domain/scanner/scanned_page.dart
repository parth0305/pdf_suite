import 'package:folio/domain/scanner/jpeg_info.dart';

/// One captured page: the JPEG exactly as the platform produced it.
///
/// The bytes are never decoded or re-encoded. They go into the PDF untouched
/// under `/DCTDecode`, which is why a ten-page scan is the size of ten
/// photographs rather than of ten raw bitmaps.
class ScannedPage {
  ScannedPage(this.jpeg) : info = jpegInfo(jpeg);

  final List<int> jpeg;
  final JpegInfo info;
}
