import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// An annotation already present in a document.
class SavedAnnotation {
  const SavedAnnotation({
    required this.objectNumber,
    required this.pageIndex,
    required this.subtype,
    required this.rectPt,
    required this.rawDictionary,
    this.colorArgb,
    this.strokeWidth,
    this.reconstructed,
  });

  final int objectNumber;
  final int pageIndex;

  /// The subtype name without its leading slash, e.g. `Highlight`.
  final String subtype;

  final TextRect rectPt;

  /// The dictionary exactly as it appears in the file. Geometry is copied out
  /// of this verbatim, never re-emitted from parsed doubles.
  final String rawDictionary;

  final int? colorArgb;
  final double? strokeWidth;

  /// The annotation rebuilt as one of Folio's own types, when its geometry can
  /// be read. Null means Folio cannot regenerate an appearance for it.
  final Annotation? reconstructed;

  /// Colour and width can be changed only when an appearance can be rebuilt.
  bool get restylable => reconstructed != null;
}

/// Reads annotations already present in a document.
///
/// Deliberately narrow: it reads the five fields an edit needs and the
/// geometry key each modelled subtype implies. It resolves nothing else.
class PdfAnnotationReader {
  PdfAnnotationReader._(this._byPage);

  final Map<int, List<SavedAnnotation>> _byPage;

  static PdfAnnotationReader parse(String pdfText) {
    final index = PdfObjectIndex.parse(pdfText);
    final pages = PdfObjectReader.parse(pdfText);
    final byPage = <int, List<SavedAnnotation>>{};

    for (var pageIndex = 0; ; pageIndex++) {
      final page = pages.pageAt(pageIndex);
      if (page == null) break;

      final found = <SavedAnnotation>[];
      for (final ref in page.existingAnnotRefs) {
        final number = int.parse(ref.split(' ').first);
        final dict = index.bodyOf(number);
        // A dangling reference is a damaged document, not a reason to refuse
        // the whole page.
        if (dict == null) continue;

        final annotation = _read(number, pageIndex, dict);
        if (annotation != null) found.add(annotation);
      }
      byPage[pageIndex] = found;
    }

    return PdfAnnotationReader._(byPage);
  }

  List<SavedAnnotation> onPage(int pageIndex) =>
      List.unmodifiable(_byPage[pageIndex] ?? const []);

  /// Every annotation in the document, in page then reference order.
  ///
  /// Callers must not iterate pages until one comes back empty: a document
  /// with annotations only on page 3 would stop at page 1.
  List<SavedAnnotation> get all => List.unmodifiable([
    for (final page in _byPage.keys.toList()..sort()) ..._byPage[page]!,
  ]);

  static SavedAnnotation? _read(int number, int pageIndex, String dict) {
    final subtype = RegExp(r'/Subtype\s*/(\w+)').firstMatch(dict)?.group(1);
    final rect = _numbersIn(dict, 'Rect');
    if (subtype == null || rect.length < 4) return null;

    final rectPt = TextRect(
      left: rect[0],
      bottom: rect[1],
      right: rect[2],
      top: rect[3],
    );
    final colour = _colourOf(dict);
    final width = _widthOf(dict);

    return SavedAnnotation(
      objectNumber: number,
      pageIndex: pageIndex,
      subtype: subtype,
      rectPt: rectPt,
      rawDictionary: dict,
      colorArgb: colour,
      strokeWidth: width,
      reconstructed: _reconstruct(
        subtype: subtype,
        pageIndex: pageIndex,
        dict: dict,
        rectPt: rectPt,
        colorArgb: colour ?? 0xFF000000,
        strokeWidth: width ?? 2,
      ),
    );
  }

  /// Rebuilds one of Folio's own annotation types from the geometry key the
  /// subtype implies, or returns null when that geometry is absent.
  static Annotation? _reconstruct({
    required String subtype,
    required int pageIndex,
    required String dict,
    required TextRect rectPt,
    required int colorArgb,
    required double strokeWidth,
  }) {
    if (subtype == 'Text') {
      return StickyNote(
        pageIndex: pageIndex,
        // /Rect is [left bottom right top]; the anchor is the top-left.
        anchorPt: PdfPoint(rectPt.left, rectPt.top),
        contents: _contentsOf(dict) ?? '',
        colorArgb: colorArgb,
      );
    }

    final markupKind = switch (subtype) {
      'Highlight' => MarkupKind.highlight,
      'Underline' => MarkupKind.underline,
      'StrikeOut' => MarkupKind.strikeOut,
      _ => null,
    };

    if (markupKind != null) {
      final quads = _numbersIn(dict, 'QuadPoints');
      if (quads.length < 8) return null;
      return TextMarkup(
        kind: markupKind,
        pageIndex: pageIndex,
        quads: [
          // Eight numbers per quad: upper-left, upper-right, lower-left,
          // lower-right (ISO 32000-1 Table 179).
          for (var i = 0; i + 7 < quads.length; i += 8)
            TextRect(
              left: quads[i],
              top: quads[i + 1],
              right: quads[i + 2],
              bottom: quads[i + 5],
            ),
        ],
        colorArgb: colorArgb,
      );
    }

    List<PdfPoint>? points;
    DrawingKind? kind;

    switch (subtype) {
      case 'Ink':
        final groups = _subArraysIn(dict, 'InkList');
        final built = [
          for (final flat in groups)
            [
              for (var i = 0; i + 1 < flat.length; i += 2)
                PdfPoint(flat[i], flat[i + 1]),
            ],
        ].where((s) => s.length >= 2).toList();
        if (built.isEmpty) return null;
        return DrawingAnnotation(
          kind: DrawingKind.ink,
          pageIndex: pageIndex,
          strokes: built,
          colorArgb: colorArgb,
          strokeWidth: strokeWidth,
        );
      case 'Square':
        kind = DrawingKind.rectangle;
        points = [
          PdfPoint(rectPt.left, rectPt.bottom),
          PdfPoint(rectPt.right, rectPt.top),
        ];
      case 'Circle':
        kind = DrawingKind.ellipse;
        points = [
          PdfPoint(rectPt.left, rectPt.bottom),
          PdfPoint(rectPt.right, rectPt.top),
        ];
      case 'Line':
        final l = _numbersIn(dict, 'L');
        if (l.length < 4) return null;
        // /LE marks an arrow; without it, a plain line.
        kind = dict.contains('/LE') ? DrawingKind.arrow : DrawingKind.line;
        points = [PdfPoint(l[0], l[1]), PdfPoint(l[2], l[3])];
      default:
        return null;
    }

    return DrawingAnnotation(
      kind: kind,
      pageIndex: pageIndex,
      strokes: [points],
      colorArgb: colorArgb,
      strokeWidth: strokeWidth,
    );
  }

  /// The bracketed sub-arrays of [key], each as its own number list.
  ///
  /// /InkList is an array of stroke arrays. Flattening it joins the strokes,
  /// so a regenerated appearance draws a line through every gap.
  static List<List<double>> _subArraysIn(String dict, String key) {
    final open = dict.indexOf('/$key');
    if (open < 0) return const [];
    final start = dict.indexOf('[', open);
    if (start < 0) return const [];

    var depth = 0;
    var end = -1;
    for (var i = start; i < dict.length; i++) {
      if (dict[i] == '[') depth++;
      if (dict[i] == ']') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return const [];

    final inner = dict.substring(start + 1, end);
    final groups = RegExp(r'\[([^\]]*)\]').allMatches(inner).toList();
    final source = groups.isEmpty
        ? [inner]
        : groups.map((m) => m.group(1)!).toList();

    return [
      for (final g in source)
        RegExp(
          r'-?\d+(?:\.\d+)?',
        ).allMatches(g).map((m) => double.parse(m.group(0)!)).toList(),
    ];
  }

  /// The `/Contents` literal string, with PDF escapes undone.
  static String? _contentsOf(String dict) {
    final start = dict.indexOf('/Contents');
    if (start < 0) return null;
    final open = dict.indexOf('(', start);
    if (open < 0) return null;

    final buffer = StringBuffer();
    var depth = 0;
    for (var i = open; i < dict.length; i++) {
      final c = dict[i];
      if (c == r'\' && i + 1 < dict.length) {
        buffer.write(dict[i + 1]);
        i++;
        continue;
      }
      if (c == '(') {
        depth++;
        if (depth == 1) continue;
      }
      if (c == ')') {
        depth--;
        if (depth == 0) return buffer.toString();
      }
      buffer.write(c);
    }
    return null;
  }

  /// Every number inside the bracketed value of [key], nesting flattened.
  static List<double> _numbersIn(String dict, String key) {
    final open = dict.indexOf('/$key');
    if (open < 0) return const [];
    final start = dict.indexOf('[', open);
    if (start < 0) return const [];

    var depth = 0;
    var end = -1;
    for (var i = start; i < dict.length; i++) {
      if (dict[i] == '[') depth++;
      if (dict[i] == ']') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return const [];

    return RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(dict.substring(start, end))
        .map((m) => double.parse(m.group(0)!))
        .toList();
  }

  /// `/C [r g b]` holds components in 0..1, not bytes.
  static int? _colourOf(String dict) {
    final c = _numbersIn(dict, 'C');
    if (c.length < 3) return null;
    int channel(double v) => (v.clamp(0, 1) * 255).round();
    return (0xFF << 24) |
        (channel(c[0]) << 16) |
        (channel(c[1]) << 8) |
        channel(c[2]);
  }

  static double? _widthOf(String dict) {
    final match = RegExp(
      r'/BS\s*<<[^>]*?/W\s+(-?\d+(?:\.\d+)?)',
    ).firstMatch(dict);
    return match == null ? null : double.parse(match.group(1)!);
  }
}
