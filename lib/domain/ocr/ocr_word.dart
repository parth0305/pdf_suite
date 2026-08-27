/// One recognised word and where it sits in the source image.
///
/// Coordinates are in IMAGE PIXELS with the origin at the top-left, which is
/// what hOCR reports. Converting to PDF points - origin bottom-left - is the
/// text layer's job, and doing it here would bury a y-flip in a parser.
class OcrWord {
  const OcrWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
}

/// What OCR produced for one page.
///
/// [words] is empty when the engine could only supply plain text - iOS, where
/// the hOCR call hangs. [lines] is always populated, so a caller can fall back
/// to placing whole lines when there are no word boxes.
class OcrPage {
  const OcrPage({required this.lines, this.words = const []});

  final List<String> lines;
  final List<OcrWord> words;

  bool get hasPositions => words.isNotEmpty;
}
