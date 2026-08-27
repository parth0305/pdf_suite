import 'package:folio/domain/ocr/ocr_word.dart';

/// Reads Tesseract's hOCR output into positioned words.
///
/// hOCR is HTML, but this is deliberately not an HTML parser: it looks for the
/// `ocrx_word` spans and their `bbox` titles and ignores everything else. A
/// general parser would be far more code for a format that Tesseract emits in
/// one shape.
OcrPage parseHocr(String hocr) {
  final words = <OcrWord>[];
  final lines = <String>[];

  // Split on line starts rather than matching each line span. hOCR nests word
  // spans inside line spans, so a non-greedy `(.*?)</span>` stops at the first
  // WORD's closing tag, not the line's - which silently truncated every line
  // to one word.
  final chunks = hocr.split(_lineStart);

  for (final chunk in chunks.skip(1)) {
    final lineWords = <String>[];

    for (final match in _wordSpan.allMatches(chunk)) {
      final text = _unescape(match.group(2)!).trim();
      if (text.isEmpty) continue;

      final box = _bbox.firstMatch(match.group(1)!);
      // A word with no box cannot be placed. Defaulting it to the origin would
      // stack unplaceable words in the page corner.
      if (box == null) continue;

      lineWords.add(text);
      words.add(
        OcrWord(
          text: text,
          left: int.parse(box.group(1)!),
          top: int.parse(box.group(2)!),
          right: int.parse(box.group(3)!),
          bottom: int.parse(box.group(4)!),
        ),
      );
    }

    if (lineWords.isNotEmpty) lines.add(lineWords.join(' '));
  }

  return OcrPage(lines: lines, words: words);
}

/// ocr_header and ocr_caption are lines too. Matching only `ocr_line` drops
/// every heading, which looks like OCR failing to read large text.
final _lineStart = RegExp(
  r"<span class='ocr_(?:line|header|caption|textfloat)'",
);

final _wordSpan = RegExp(
  r"<span class='ocrx_word'[^>]*title='([^']*)'[^>]*>(.*?)</span>",
  dotAll: true,
);

final _bbox = RegExp(r'bbox (\d+) (\d+) (\d+) (\d+)');

/// hOCR is HTML, so the five XML entities can appear in recognised text.
String _unescape(String s) => s
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
