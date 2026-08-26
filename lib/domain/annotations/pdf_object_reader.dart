import 'package:folio/core/errors/app_failure.dart';

/// A page object located in a PDF's text.
class PdfPageObject {
  const PdfPageObject({
    required this.objectNumber,
    required this.rawDictionary,
    required this.existingAnnotRefs,
  });

  final int objectNumber;

  /// The full dictionary including its outer `<<` and `>>`.
  final String rawDictionary;

  /// Indirect references already in `/Annots`, e.g. `7 0 R`.
  final List<String> existingAnnotRefs;
}

/// A deliberately minimal PDF reader: it finds page dictionaries and re-emits
/// them with an added `/Annots`, and does nothing else.
///
/// It honours incremental updates: when an object number is defined more than
/// once, the LAST definition wins, which is what a reader walking the trailer
/// chain backwards would see. Reading a superseded dictionary would merge into
/// a stale `/Annots` and orphan every annotation saved before it.
///
/// This is not a general PDF parser and must not become one. If a caller needs
/// more than page dictionaries, that is a signal to reconsider scope rather
/// than to grow this file.
class PdfObjectReader {
  PdfObjectReader._(this._pages, this.usesXrefStream);

  final List<PdfPageObject> _pages;

  /// True when the document uses PDF 1.5+ cross-reference streams, for which
  /// the incremental-update technique does not hold.
  final bool usesXrefStream;

  static PdfObjectReader parse(String pdfText) {
    // Object number -> its latest dictionary, plus the order object numbers
    // first appear, so page order survives the de-duplication.
    final latest = <int, String>{};
    final order = <int>[];

    // Dictionaries are matched by brace balance rather than a regex, so nested
    // << >> cannot terminate one early - the spike's regex broke on exactly
    // that.
    for (final start in RegExp(r'(\d+)\s+0\s+obj').allMatches(pdfText)) {
      final open = pdfText.indexOf('<<', start.end);
      if (open < 0) continue;
      final close = _matchingClose(pdfText, open);
      if (close < 0) continue;

      final dict = pdfText.substring(open, close + 2);
      // /Type /Page but not /Pages: the next character must not be a letter.
      if (!RegExp(r'/Type\s*/Page(?![a-zA-Z])').hasMatch(dict)) continue;

      final number = int.parse(start.group(1)!);
      if (!latest.containsKey(number)) order.add(number);
      latest[number] = dict;
    }

    final pages = [
      for (final number in order)
        PdfPageObject(
          objectNumber: number,
          rawDictionary: latest[number]!,
          existingAnnotRefs: _readAnnotRefs(latest[number]!),
        ),
    ];

    return PdfObjectReader._(pages, RegExp(r'/Type\s*/XRef').hasMatch(pdfText));
  }

  /// Index of the `>>` closing the `<<` at [openIndex], honouring nesting.
  static int _matchingClose(String text, int openIndex) {
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

  static List<String> _readAnnotRefs(String dict) {
    final match = RegExp(r'/Annots\s*\[([^\]]*)\]').firstMatch(dict);
    if (match == null) {
      // `/Annots 9 0 R` - the array lives in its own object. Merging emits an
      // inline array, which would REPLACE that reference and orphan every
      // annotation it holds. Refuse rather than destroy another tool's work.
      if (RegExp(r'/Annots\s+\d+\s+\d+\s+R').hasMatch(dict)) {
        throw const UnsupportedPdfStructure(
          technicalDetail: '/Annots is an indirect reference',
        );
      }
      return const [];
    }
    return RegExp(r'\d+\s+\d+\s+R')
        .allMatches(match.group(1)!)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ' '))
        .toList();
  }

  PdfPageObject? pageAt(int index) =>
      index >= 0 && index < _pages.length ? _pages[index] : null;

  /// Re-emits [page]'s dictionary with [newRefs] added to `/Annots`.
  ///
  /// Existing references are merged, never replaced: replacing them would
  /// silently delete a user's existing annotations.
  String withAnnots(PdfPageObject page, List<String> newRefs) {
    final all = [...page.existingAnnotRefs, ...newRefs];
    final annots = '/Annots [${all.join(' ')}]';

    final dict = page.rawDictionary;
    if (page.existingAnnotRefs.isEmpty) {
      final body = dict.substring(2, dict.length - 2).trimRight();
      return '<< $body $annots >>';
    }

    return dict.replaceFirst(RegExp(r'/Annots\s*\[[^\]]*\]'), annots);
  }
}
