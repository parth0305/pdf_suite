import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/domain/scanner/scanned_page.dart';

/// A4 in points, the page size a scan is fitted into.
const double kA4WidthPt = 595;
const double kA4HeightPt = 842;

/// Builds a complete PDF from scratch, one `/DCTDecode` page per image.
///
/// Unlike `writePdfDocument` this has no original to rewrite: a scan is a new
/// document with no history, so there is no incremental update to append to
/// and no objects to carry over.
Uint8List buildScannedDocument(List<ScannedPage> pages) {
  if (pages.isEmpty) {
    throw ArgumentError.value(pages, 'pages', 'a scan needs at least one page');
  }

  // 1 catalog, 2 page tree, then three objects per page.
  final pageNumbers = <int>[];
  final bodies = <int, List<int>>{};
  var next = 3;

  for (final page in pages) {
    final imageNumber = next++;
    final contentNumber = next++;
    final pageNumber = next++;
    pageNumbers.add(pageNumber);

    bodies[imageNumber] = [
      ...latin1.encode(
        '<< /Type /XObject /Subtype /Image '
        '/Width ${page.info.width} /Height ${page.info.height} '
        '/ColorSpace ${page.info.colorSpace} /BitsPerComponent 8 '
        // /Length is the JPEG's own byte count: it is embedded untouched, so
        // any other value means the bytes were mangled on the way in.
        '/Length ${page.jpeg.length} /Filter /DCTDecode >>\nstream\n',
      ),
      ...page.jpeg,
      ...latin1.encode('\nendstream'),
    ];

    final fit = _fitToA4(page.info.width, page.info.height);
    final content =
        'q\n'
        '${_n(fit.width)} 0 0 ${_n(fit.height)} ${_n(fit.x)} ${_n(fit.y)} cm\n'
        '/ScIm0 Do\n'
        'Q\n';
    bodies[contentNumber] = latin1.encode(
      '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    );

    bodies[pageNumber] = latin1.encode(
      '<< /Type /Page /Parent 2 0 R '
      '/MediaBox [0 0 ${_n(kA4WidthPt)} ${_n(kA4HeightPt)}] '
      '/Resources << /XObject << /ScIm0 $imageNumber 0 R >> >> '
      '/Contents $contentNumber 0 R >>',
    );
  }

  bodies[1] = latin1.encode('<< /Type /Catalog /Pages 2 0 R >>');
  bodies[2] = latin1.encode(
    '<< /Type /Pages /Kids [${pageNumbers.map((n) => '$n 0 R').join(' ')}] '
    '/Count ${pages.length} >>',
  );

  // The binary comment marks the file as carrying 8-bit data, so tools do not
  // mangle it as text. A JPEG guarantees there is some.
  final out = <int>[...latin1.encode('%PDF-1.4\n%âãÏÓ\n')];
  final offsets = <int, int>{};

  for (var n = 1; n < next; n++) {
    offsets[n] = out.length;
    out
      ..addAll(latin1.encode('$n 0 obj\n'))
      ..addAll(bodies[n]!)
      ..addAll(latin1.encode('\nendobj\n'));
  }

  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n0 $next\n')
    ..writeln('0000000000 65535 f ');
  for (var n = 1; n < next; n++) {
    buffer.writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer
    ..writeln('trailer')
    ..writeln('<< /Size $next /Root 1 0 R >>')
    ..writeln('startxref')
    ..writeln('$xrefOffset')
    ..write('%%EOF\n');

  return Uint8List.fromList([...out, ...latin1.encode(buffer.toString())]);
}

/// The image's aspect ratio fitted inside A4 and centred.
///
/// A landscape image is fitted within the portrait page rather than rotating
/// the page: rotating would make a mixed scan alternate orientation, which is
/// worse to read and worse to print.
({double x, double y, double width, double height}) _fitToA4(
  int imageWidth,
  int imageHeight,
) {
  final scale = (kA4WidthPt / imageWidth) < (kA4HeightPt / imageHeight)
      ? kA4WidthPt / imageWidth
      : kA4HeightPt / imageHeight;

  final width = imageWidth * scale;
  final height = imageHeight * scale;

  return (
    x: (kA4WidthPt - width) / 2,
    y: (kA4HeightPt - height) / 2,
    width: width,
    height: height,
  );
}

String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}
