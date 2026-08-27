enum WatermarkRotation { diagonal, horizontal }

/// An image stamped across every page, instead of text.
///
/// Kept as a separate type rather than nullable fields on [Watermark]: a text
/// mark has a font size and a colour, an image mark has pixels and a scale,
/// and a class carrying both with half of them null invites drawing neither.
class ImageWatermark {
  const ImageWatermark({
    required this.rgba,
    required this.pixelWidth,
    required this.pixelHeight,
    this.opacity = 0.3,
    this.scale = 0.5,
    this.rotation = WatermarkRotation.diagonal,
  });

  final List<int> rgba;
  final int pixelWidth;
  final int pixelHeight;

  /// 0 is invisible, 1 is opaque.
  final double opacity;

  /// Fraction of the page's shorter side the mark spans.
  final double scale;

  final WatermarkRotation rotation;

  bool get isUsable =>
      pixelWidth > 0 &&
      pixelHeight > 0 &&
      rgba.length == pixelWidth * pixelHeight * 4;

  double get aspectRatio => pixelWidth / pixelHeight;
}

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
