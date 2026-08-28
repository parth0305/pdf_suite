import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// Where the number sits on the page.
enum NumberPosition {
  bottomCentre,
  bottomRight,
  bottomLeft,
  topCentre,
  topRight,
  topLeft,
}

/// How the number reads.
enum NumberFormat {
  /// `7`
  plain,

  /// `Page 7`
  labelled,

  /// `7 of 12`
  ofTotal,

  /// `Page 7 of 12`
  labelledOfTotal,
}

/// The resource name Folio gives the numbering font.
///
/// Distinctive, like the watermark's, so numbering can be told apart from a
/// page's own resources.
const numberFontName = 'PgF1';

/// What to stamp on each page.
class PageNumbering {
  const PageNumbering({
    this.position = NumberPosition.bottomCentre,
    this.format = NumberFormat.plain,
    this.fontSizePt = 10,
    this.startAt = 1,
    this.skipFirst = false,
    this.marginPt = 36,
  });

  final NumberPosition position;
  final NumberFormat format;
  final double fontSizePt;

  /// The number printed on the first numbered page.
  ///
  /// A chapter that continues from another document starts at 47, not 1.
  final int startAt;

  /// Leave the first page unnumbered, which is what a title page wants.
  final bool skipFirst;

  /// Distance from the page edge.
  final double marginPt;
}

/// The text for one page, or null when this page is not numbered.
///
/// [pageIndex] is zero-based; [pageCount] is the whole document.
String? numberTextFor(PageNumbering numbering, int pageIndex, int pageCount) {
  if (numbering.skipFirst && pageIndex == 0) return null;

  // Skipping the first page must not make the second page "2" when the user
  // asked to start at 1 - the numbering starts where the numbers start.
  final offset = numbering.skipFirst ? 1 : 0;
  final shown = numbering.startAt + pageIndex - offset;
  final total = pageCount - offset + numbering.startAt - 1;

  return switch (numbering.format) {
    NumberFormat.plain => '$shown',
    NumberFormat.labelled => 'Page $shown',
    NumberFormat.ofTotal => '$shown of $total',
    NumberFormat.labelledOfTotal => 'Page $shown of $total',
  };
}

/// Roughly how wide [text] will be at [fontSizePt] in a text face.
///
/// The fallback for when no font has been measured. Folio now embeds one, so
/// [numberOrigin] takes a real width instead; this remains for callers that
/// have no font to hand.
double estimatedWidth(String text, double fontSizePt) =>
    text.length * fontSizePt * 0.5;

/// Where the number's baseline goes, in PDF points.
({double x, double y}) numberOrigin(
  PageNumbering numbering,
  String text,
  TextRect mediaBox, {

  /// The measured width in thousandths of the text size, where the caller has
  /// a font to measure with. Right-aligning by an estimate puts the number a
  /// few points off the margin, which shows up as a ragged edge down a
  /// hundred-page document.
  double? widthPerMille,
}) {
  final width = widthPerMille == null
      ? estimatedWidth(text, numbering.fontSizePt)
      : widthPerMille * numbering.fontSizePt / 1000;

  final x = switch (numbering.position) {
    NumberPosition.bottomLeft ||
    NumberPosition.topLeft => mediaBox.left + numbering.marginPt,
    NumberPosition.bottomRight ||
    NumberPosition.topRight => mediaBox.right - numbering.marginPt - width,
    NumberPosition.bottomCentre ||
    NumberPosition.topCentre => mediaBox.left + (mediaBox.width - width) / 2,
  };

  final y = switch (numbering.position) {
    NumberPosition.bottomLeft ||
    NumberPosition.bottomCentre ||
    NumberPosition.bottomRight => mediaBox.bottom + numbering.marginPt,
    // Text is drawn from its baseline, so a top-positioned number needs the
    // font size subtracted or it sits half off the page.
    NumberPosition.topLeft ||
    NumberPosition.topCentre ||
    NumberPosition.topRight =>
      mediaBox.top - numbering.marginPt - numbering.fontSizePt,
  };

  return (x: x, y: y);
}

/// The content stream that draws one page's number.
///
/// Balanced q/Q: an unbalanced graphics state corrupts everything drawn after
/// it on the page.
String pageNumberContentStream(
  PageNumbering numbering,
  String text, {
  required TextRect mediaBox,

  /// The text already encoded for the embedded font, as a hex string of glyph
  /// indices, with its measured width in thousandths of the text size.
  ///
  /// Absent means the caller has no font and the text is written as literal
  /// bytes - which only works for characters the reader's standard encoding
  /// happens to cover.
  ({String hex, double width})? encoded,
}) {
  final origin = numberOrigin(
    numbering,
    text,
    mediaBox,
    widthPerMille: encoded?.width,
  );

  final show = encoded == null
      ? '${pdfString(text)} Tj'
      : '<${encoded.hex}> Tj';

  return 'q\n'
      'BT\n'
      '/$numberFontName ${pdfNumber(numbering.fontSizePt)} Tf\n'
      '0 g\n'
      '1 0 0 1 ${pdfNumber(origin.x)} ${pdfNumber(origin.y)} Tm\n'
      '$show\n'
      'ET\n'
      'Q\n';
}
