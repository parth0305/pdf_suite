part of 'annotation.dart';

/// A raster placed on the page: a photographed signature.
///
/// Kept apart from [DrawingAnnotation] because the two are not the same thing
/// wearing different clothes. A drawn signature is strokes, which scale
/// without loss and can be restyled. A photographed one is pixels with a
/// transparency mask, and pretending otherwise would mean tracing the
/// photograph - which is a different feature with different failure modes.
class ImageAnnotation extends Annotation {
  const ImageAnnotation({
    required this.pageIndex,
    required this.rect,
    required this.rgba,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  @override
  final int pageIndex;

  /// Where it sits, in PDF points.
  final TextRect rect;

  /// RGBA, where alpha is what makes the paper disappear.
  final List<int> rgba;

  final int pixelWidth;
  final int pixelHeight;

  /// A stamp, because that is what PDF calls a graphic placed on a page. It is
  /// not an /Ink annotation: there are no strokes to record.
  @override
  String get pdfSubtype => 'Stamp';
}
