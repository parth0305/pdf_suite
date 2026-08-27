import 'package:folio/domain/ocr/ocr_word.dart';

/// Builds the invisible text a scanned page carries so it can be searched.
///
/// Text render mode 3 paints nothing and stays extractable - the same
/// mechanism redaction uses to rebuild a rasterised page's text layer.
///
/// [imageWidth] and [imageHeight] are the pixel dimensions the OCR ran on;
/// [pageWidth], [pageHeight], [offsetX] and [offsetY] describe where that
/// image sits on the PDF page, because a scan is fitted into A4 and centred
/// rather than filling it.
String ocrTextLayer({
  required OcrPage page,
  required int imageWidth,
  required int imageHeight,
  required double pageWidth,
  required double pageHeight,
  required double offsetX,
  required double offsetY,
}) {
  if (page.hasPositions) {
    return _positioned(
      page.words,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  return _approximate(
    page.lines,
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    offsetX: offsetX,
    offsetY: offsetY,
  );
}

/// One `Tj` per word, at the box OCR reported.
///
/// Image pixels have their origin at the top-left and PDF points at the
/// bottom-left, so the vertical axis is flipped. Getting that wrong puts every
/// word on the mirror image of its line, which still looks like a text layer.
String _positioned(
  List<OcrWord> words, {
  required int imageWidth,
  required int imageHeight,
  required double pageWidth,
  required double pageHeight,
  required double offsetX,
  required double offsetY,
}) {
  final scaleX = pageWidth / imageWidth;
  final scaleY = pageHeight / imageHeight;
  final buffer = StringBuffer();

  for (final w in words) {
    final text = _drawable(w.text);
    if (text.isEmpty) continue;

    final x = offsetX + w.left * scaleX;
    // The word's BASELINE is what Tm positions, so the bottom of the box is
    // the right edge to use after the flip.
    final y = offsetY + (imageHeight - w.bottom) * scaleY;
    final size = w.height * scaleY;

    buffer.writeln(
      'BT 3 Tr /OcF1 ${_n(size)} Tf '
      '1 0 0 1 ${_n(x)} ${_n(y)} Tm '
      '${_escaped(text)} Tj ET',
    );
  }

  return buffer.toString();
}

/// One `Tj` per line, spread evenly down the page.
///
/// Used only where the engine cannot report word boxes. The text is searchable
/// and copyable, but a search highlight lands near the right line rather than
/// on the word. That is a real compromise and is documented as one - it is not
/// presented as equivalent to the positioned path.
String _approximate(
  List<String> lines, {
  required double pageWidth,
  required double pageHeight,
  required double offsetX,
  required double offsetY,
}) {
  if (lines.isEmpty) return '';

  final step = pageHeight / (lines.length + 1);
  final buffer = StringBuffer();

  for (var i = 0; i < lines.length; i++) {
    final text = _drawable(lines[i]);
    if (text.isEmpty) continue;

    // Lines are laid out top-down, so the first line gets the HIGHEST y.
    final y = offsetY + pageHeight - step * (i + 1);

    buffer.writeln(
      'BT 3 Tr /OcF1 ${_n(step * 0.6)} Tf '
      '1 0 0 1 ${_n(offsetX)} ${_n(y)} Tm '
      '${_escaped(text)} Tj ET',
    );
  }

  return buffer.toString();
}

/// Drops characters a non-embedded standard-14 font cannot represent.
///
/// The same rule redaction uses: WinAnsiEncoding covers Latin-1, and emitting
/// anything else writes a byte that means a different character. A dropped
/// character loses searchability for that character and nothing more.
String _drawable(String s) {
  final kept = StringBuffer();
  for (final unit in s.codeUnits) {
    if (unit > 0x20 && unit <= 0xFF) kept.writeCharCode(unit);
    if (unit == 0x20) kept.write(' ');
  }
  return kept.toString().trim();
}

String _escaped(String s) =>
    '(${s.replaceAllMapped(RegExp(r'[\\()]'), (m) => '\\${m[0]}')})';

String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}
