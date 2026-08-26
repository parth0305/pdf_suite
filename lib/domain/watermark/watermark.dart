enum WatermarkRotation { diagonal, horizontal }

/// A text mark stamped across every page of a document.
///
/// This is page content, not an annotation: an annotation would be a stamp,
/// which SP-3e already ships and which any viewer can delete. Being part of
/// the page is the point.
class Watermark {
  const Watermark({
    required this.text,
    this.fontSizePt = 48,
    this.colorArgb = 0xFF9E9E9E,
    this.opacity = 0.3,
    this.rotation = WatermarkRotation.diagonal,
  });

  final String text;
  final double fontSizePt;
  final int colorArgb;

  /// 0 is invisible, 1 is opaque.
  final double opacity;

  final WatermarkRotation rotation;

  Watermark copyWith({
    String? text,
    double? fontSizePt,
    int? colorArgb,
    double? opacity,
    WatermarkRotation? rotation,
  }) => Watermark(
    text: text ?? this.text,
    fontSizePt: fontSizePt ?? this.fontSizePt,
    colorArgb: colorArgb ?? this.colorArgb,
    opacity: opacity ?? this.opacity,
    rotation: rotation ?? this.rotation,
  );
}
