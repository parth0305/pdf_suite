import 'package:folio/domain/engine/pdf_types.dart';

enum MarkupKind { highlight, underline, strikeOut }

/// One text-markup annotation staged for writing.
///
/// [quads] come straight from `PageText.charRects`, which are already PDF user
/// space with y-up coordinates, so no conversion is needed anywhere.
class TextMarkup {
  const TextMarkup({
    required this.kind,
    required this.pageIndex,
    required this.quads,
    this.colorArgb = 0xFFFFFF00,
  });

  final MarkupKind kind;
  final int pageIndex;
  final List<TextRect> quads;
  final int colorArgb;

  /// The PDF annotation subtype name. Note StrikeOut, not Strikethrough.
  String get pdfSubtype => switch (kind) {
    MarkupKind.highlight => 'Highlight',
    MarkupKind.underline => 'Underline',
    MarkupKind.strikeOut => 'StrikeOut',
  };

  /// Eight numbers per quad, ordered upper-left, upper-right, lower-left,
  /// lower-right per ISO 32000-1 Table 179.
  ///
  /// Clockwise ordering looks natural and is wrong: viewers render it as a
  /// bowtie or not at all.
  List<double> get quadPoints => [
    for (final q in quads) ...[
      q.left,
      q.top,
      q.right,
      q.top,
      q.left,
      q.bottom,
      q.right,
      q.bottom,
    ],
  ];

  TextRect get boundingRect => TextRect(
    left: quads.map((q) => q.left).reduce((a, b) => a < b ? a : b),
    right: quads.map((q) => q.right).reduce((a, b) => a > b ? a : b),
    top: quads.map((q) => q.top).reduce((a, b) => a > b ? a : b),
    bottom: quads.map((q) => q.bottom).reduce((a, b) => a < b ? a : b),
  );

  /// PDF `/C` components, each 0..1, space separated.
  String get pdfColour {
    String c(int shift) =>
        (((colorArgb >> shift) & 0xFF) / 255).toStringAsFixed(3);
    return '${c(16)} ${c(8)} ${c(0)}'.replaceAll(RegExp(r'\.000\b'), '');
  }
}
