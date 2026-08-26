part of 'annotation.dart';

/// A comment anchored to a point on the page.
///
/// Written as a PDF /Text annotation, which viewers draw as an icon and open
/// as a popup. It carries NO appearance stream: PDFium draws the icon itself,
/// and generating one would only risk disagreeing with what other viewers
/// draw. The text lives in /Contents, where it stays searchable and copyable.
final class StickyNote extends Annotation {
  const StickyNote({
    required this.pageIndex,
    required this.anchorPt,
    required this.contents,
    this.colorArgb = 0xFFFFC107,
  });

  @override
  final int pageIndex;

  /// Top-left of the icon, in PDF user space.
  final PdfPoint anchorPt;

  final String contents;
  final int colorArgb;

  @override
  String get pdfSubtype => 'Text';

  /// PDF's conventional note icon size. Viewers draw the icon at a fixed size
  /// regardless, so there is nothing for the user to size.
  static const double iconSizePt = 20;
}
