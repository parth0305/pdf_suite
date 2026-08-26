/// Maps a PDF object number to its latest dictionary body.
///
/// This indexes `N 0 obj ... endobj` spans and stops. It resolves nothing,
/// types nothing, and reads no streams - it exists so that page and annotation
/// readers can share two mechanics that are genuinely general:
///
///  - dictionaries matched by brace balance, so a nested `<< >>` cannot end one
///    early;
///  - the LAST definition of an object number wins, which is what a reader
///    walking the trailer chain backwards sees. Reading a superseded
///    dictionary silently orphans everything the newer one references.
class PdfObjectIndex {
  PdfObjectIndex._(this._bodies, this._order, this.usesXrefStream);

  final Map<int, String> _bodies;
  final List<int> _order;

  /// True for PDF 1.5+ cross-reference streams, where the incremental-update
  /// technique does not hold.
  final bool usesXrefStream;

  static PdfObjectIndex parse(String pdfText) {
    final bodies = <int, String>{};
    final order = <int>[];

    for (final start in RegExp(r'(\d+)\s+0\s+obj').allMatches(pdfText)) {
      final open = pdfText.indexOf('<<', start.end);
      if (open < 0) continue;

      // `<<` must belong to THIS object, not a later one.
      final end = pdfText.indexOf('endobj', start.end);
      if (end >= 0 && open > end) continue;

      final close = matchingClose(pdfText, open);
      if (close < 0) continue;

      final number = int.parse(start.group(1)!);
      if (!bodies.containsKey(number)) order.add(number);
      bodies[number] = pdfText.substring(open, close + 2);
    }

    return PdfObjectIndex._(
      bodies,
      order,
      RegExp(r'/Type\s*/XRef').hasMatch(pdfText),
    );
  }

  /// The latest dictionary for [objectNumber], or null if there is none.
  String? bodyOf(int objectNumber) => _bodies[objectNumber];

  /// Object numbers in the order they first appear.
  Iterable<int> get objectNumbers => List.unmodifiable(_order);

  /// Index of the `>>` closing the `<<` at [openIndex], honouring nesting.
  static int matchingClose(String text, int openIndex) {
    var depth = 0;
    for (var i = openIndex; i < text.length - 1; i++) {
      if (text[i] == '<' && text[i + 1] == '<') {
        depth++;
        i++;
      } else if (text[i] == '>' && text[i + 1] == '>') {
        depth--;
        if (depth == 0) return i;
        i++;
      }
    }
    return -1;
  }
}
