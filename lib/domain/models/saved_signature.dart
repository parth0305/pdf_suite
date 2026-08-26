import 'package:folio/domain/annotations/pdf_point.dart';

/// A signature the user drew once and can place on any document.
///
/// [strokes] are normalised into a unit box with y increasing upward, matching
/// PDF user space, so placement is a multiply and an offset with no flip.
class SavedSignature {
  const SavedSignature({
    required this.id,
    required this.label,
    required this.strokes,
    required this.aspectRatio,
  });

  final int id;
  final String label;
  final List<List<PdfPoint>> strokes;

  /// Width divided by height as drawn. Placement preserves it: a stretched
  /// signature looks forged.
  final double aspectRatio;
}
