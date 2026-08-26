import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';

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
    final index = PdfObjectIndex.parse(pdfText);
    final pages = <PdfPageObject>[];

    for (final number in index.objectNumbers) {
      final dict = index.bodyOf(number)!;
      // /Type /Page but not /Pages: the next character must not be a letter.
      if (!RegExp(r'/Type\s*/Page(?![a-zA-Z])').hasMatch(dict)) continue;

      pages.add(
        PdfPageObject(
          objectNumber: number,
          rawDictionary: dict,
          existingAnnotRefs: _readAnnotRefs(dict),
        ),
      );
    }

    return PdfObjectReader._(pages, index.usesXrefStream);
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
