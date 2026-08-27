import 'package:folio/domain/annotations/pdf_point.dart';

/// How a saved signature was made.
///
/// The two are not interchangeable. A drawn signature is strokes, which scale
/// without loss; a photographed one is pixels with a transparency mask.
enum SignatureKind { drawn, photo }

/// A signature the user made once and can place on any document.
///
/// [strokes] are normalised into a unit box with y increasing upward, matching
/// PDF user space, so placement is a multiply and an offset with no flip.
class SavedSignature {
  const SavedSignature({
    required this.id,
    required this.label,
    required this.strokes,
    required this.aspectRatio,
    this.kind = SignatureKind.drawn,
    this.imageRgba,
    this.pixelWidth,
    this.pixelHeight,
  });

  final SignatureKind kind;

  /// RGBA with the paper already made transparent, for a photographed
  /// signature. Null for a drawn one.
  final List<int>? imageRgba;

  final int? pixelWidth;
  final int? pixelHeight;

  /// Whether this can actually be placed.
  ///
  /// A photographed signature with no pixels, or a drawn one with no strokes,
  /// is a row that survived a failed save; placing it would put nothing on the
  /// page while reporting success.
  bool get isPlaceable => switch (kind) {
    SignatureKind.drawn => strokes.isNotEmpty,
    SignatureKind.photo =>
      imageRgba != null && pixelWidth != null && pixelHeight != null,
  };

  final int id;
  final String label;
  final List<List<PdfPoint>> strokes;

  /// Width divided by height as drawn. Placement preserves it: a stretched
  /// signature looks forged.
  final double aspectRatio;
}
