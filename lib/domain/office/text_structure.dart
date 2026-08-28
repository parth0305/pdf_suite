import 'package:folio/domain/engine/pdf_types.dart';

/// A run of characters with no space in it, and where it sits.
class TextWord {
  const TextWord({required this.text, required this.bounds});

  final String text;
  final TextRect bounds;
}

/// One line of text as the page laid it out.
class TextLine {
  const TextLine({required this.words, required this.bounds});

  final List<TextWord> words;
  final TextRect bounds;

  String get text => words.map((w) => w.text).join(' ');
}

/// Lines that belong together.
///
/// A PDF records where glyphs sit, not that they form a paragraph. This is
/// inference, and it will get some documents wrong - which is why the app says
/// so rather than presenting the result as a faithful conversion.
class TextParagraph {
  const TextParagraph(this.lines);

  final List<TextLine> lines;

  String get text => lines.map((l) => l.text).join(' ');
}

/// The page's text as lines of words.
///
/// PDFium already breaks extracted text into lines, so the line structure is
/// read rather than guessed. Re-deriving it from glyph geometry is what turned
/// "rupees" into "ru p ees" when the OCR writer tried it.
List<TextLine> linesOf(PageText page) {
  final out = <TextLine>[];
  var words = <TextWord>[];
  var letters = StringBuffer();
  var wordRects = <TextRect>[];

  void endWord() {
    if (letters.isEmpty) return;
    words.add(TextWord(text: letters.toString(), bounds: _union(wordRects)!));
    letters = StringBuffer();
    wordRects = [];
  }

  void endLine() {
    endWord();
    if (words.isEmpty) return;
    out.add(
      TextLine(
        words: List.of(words),
        bounds: _union(words.map((w) => w.bounds).toList())!,
      ),
    );
    words = <TextWord>[];
  }

  for (var i = 0; i < page.fullText.length; i++) {
    final char = page.fullText[i];

    if (char == '\n' || char == '\r') {
      endLine();
      continue;
    }
    if (char == ' ' || char == '\t') {
      endWord();
      continue;
    }

    letters.write(char);
    if (i < page.charRects.length) wordRects.add(page.charRects[i]);
  }
  endLine();

  return out;
}

/// Lines grouped into paragraphs.
///
/// Two signals, both of which a person reads without thinking about: a gap
/// taller than the lines around it, and a line that starts further in than the
/// one before it.
List<TextParagraph> paragraphsOf(
  List<TextLine> lines, {
  double gapRatio = 1.6,
  double indentRatio = 1.5,
}) {
  if (lines.isEmpty) return const [];

  final gaps = <double>[];
  for (var i = 1; i < lines.length; i++) {
    gaps.add(lines[i - 1].bounds.bottom - lines[i].bounds.bottom);
  }

  final typicalGap = _median(gaps);
  final typicalHeight = _median(lines.map((l) => l.bounds.height).toList());

  final out = <TextParagraph>[];
  var current = <TextLine>[lines.first];

  for (var i = 1; i < lines.length; i++) {
    final gap = lines[i - 1].bounds.bottom - lines[i].bounds.bottom;
    final indent = lines[i].bounds.left - lines[i - 1].bounds.left;

    final startsAgain =
        (typicalGap > 0 && gap > typicalGap * gapRatio) ||
        (typicalHeight > 0 && indent > typicalHeight * indentRatio);

    if (startsAgain) {
      out.add(TextParagraph(List.of(current)));
      current = <TextLine>[];
    }
    current.add(lines[i]);
  }

  if (current.isNotEmpty) out.add(TextParagraph(current));
  return out;
}

/// A line split where the spacing is wide enough to be a column.
///
/// A PDF has no notion of a cell, so a table is inferred from alignment. Two
/// words a whole space apart are a phrase; two words an inch apart are two
/// columns, and the only thing separating those cases is how far apart they
/// are relative to everything else on the page.
List<String> cellsOf(TextLine line, {required double columnGap}) {
  if (line.words.isEmpty) return const [];

  final out = <String>[];
  var cell = StringBuffer(line.words.first.text);

  for (var i = 1; i < line.words.length; i++) {
    final gap = line.words[i].bounds.left - line.words[i - 1].bounds.right;

    if (gap >= columnGap) {
      out.add(cell.toString());
      cell = StringBuffer(line.words[i].text);
    } else {
      cell.write(' ');
      cell.write(line.words[i].text);
    }
  }

  return out..add(cell.toString());
}

/// How wide a gap has to be before it means a column, for these lines.
///
/// Derived from the page rather than fixed: a gap of six points separates
/// columns in a ten-point document and words in a thirty-point one.
double columnGapFor(List<TextLine> lines, {double multiple = 2.5}) {
  final gaps = <double>[];

  for (final line in lines) {
    for (var i = 1; i < line.words.length; i++) {
      gaps.add(line.words[i].bounds.left - line.words[i - 1].bounds.right);
    }
  }

  final typical = _median(gaps.where((g) => g > 0).toList());
  // Nothing to measure means nothing to split on, and a threshold of zero
  // would make every word its own column.
  return typical <= 0 ? double.infinity : typical * multiple;
}

TextRect? _union(List<TextRect> rects) {
  if (rects.isEmpty) return null;

  var left = rects.first.left;
  var right = rects.first.right;
  var top = rects.first.top;
  var bottom = rects.first.bottom;

  for (final rect in rects.skip(1)) {
    if (rect.left < left) left = rect.left;
    if (rect.right > right) right = rect.right;
    if (rect.top > top) top = rect.top;
    if (rect.bottom < bottom) bottom = rect.bottom;
  }

  return TextRect(left: left, top: top, right: right, bottom: bottom);
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;

  final sorted = List.of(values)..sort();
  final middle = sorted.length ~/ 2;

  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
