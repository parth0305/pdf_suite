part of 'annotation.dart';

enum DrawingKind { ink, rectangle, ellipse, line, arrow }

/// A freehand stroke or geometric shape staged for writing.
///
/// [points] are PDF user space, y-up. For [DrawingKind.ink] they are the
/// smoothed path; for shapes they are the two corners of the user's drag, in
/// whatever order it happened.
final class DrawingAnnotation extends Annotation {
  const DrawingAnnotation({
    required this.kind,
    required this.pageIndex,
    required this.strokes,
    this.colorArgb = 0xFF000000,
    this.strokeWidth = 2,
  });

  final DrawingKind kind;

  @override
  final int pageIndex;

  /// Sub-paths, matching what PDF's /InkList has always meant. Shapes hold a
  /// single sub-path of two corners; a signature holds one per pen stroke.
  final List<List<PdfPoint>> strokes;

  /// The first sub-path. Shapes have only one, so their code reads naturally.
  List<PdfPoint> get points => strokes.first;

  final int colorArgb;
  final double strokeWidth;

  /// PDF's /Circle draws an ellipse inscribed in its /Rect - it is not a
  /// circle. An arrow is a /Line distinguished by its line ending.
  @override
  String get pdfSubtype => switch (kind) {
    DrawingKind.ink => 'Ink',
    DrawingKind.rectangle => 'Square',
    DrawingKind.ellipse => 'Circle',
    DrawingKind.line || DrawingKind.arrow => 'Line',
  };

  /// The bounding box in PDF space. Normalised, so a drag in any direction
  /// gives the same rectangle.
  ({double left, double bottom, double right, double top}) get boundsPt {
    // Across ALL strokes: bounding only the first would give a /Rect that is
    // too small and a /BBox that clips the rest of the drawing away.
    final all = strokes.expand((s) => s);
    var left = all.first.x;
    var right = all.first.x;
    var bottom = all.first.y;
    var top = all.first.y;

    for (final p in all) {
      if (p.x < left) left = p.x;
      if (p.x > right) right = p.x;
      if (p.y < bottom) bottom = p.y;
      if (p.y > top) top = p.y;
    }
    return (left: left, bottom: bottom, right: right, top: top);
  }

  /// PDF colour components, each 0..1, space separated.
  String get pdfColour {
    String c(int shift) =>
        (((colorArgb >> shift) & 0xFF) / 255).toStringAsFixed(3);
    return '${c(16)} ${c(8)} ${c(0)}'.replaceAll(RegExp(r'\.000\b'), '');
  }
}
