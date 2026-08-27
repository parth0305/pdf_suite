import 'dart:math' as math;

/// Separates ink from paper in a photographed signature.
///
/// This is classical image processing, not AI: a luminance histogram and
/// Otsu's 1979 threshold, which is a closed-form statistical method with no
/// model, no training and no network. That matters here — the project forbids
/// AI, and "remove the background" is exactly the phrase that usually means a
/// hosted segmentation model.
///
/// What it assumes is what a photographed signature actually is: dark ink on
/// lighter paper, filling most of the frame. It does not attempt to cut a
/// signature out of a photograph of a desk.
class InkExtraction {
  const InkExtraction({
    required this.rgba,
    required this.threshold,
    required this.inkFraction,
  });

  /// RGBA, with paper made fully transparent and ink left as it was.
  final List<int> rgba;

  /// The luminance Otsu's method chose, 0-255. Useful for explaining a poor
  /// result rather than leaving the user guessing.
  final int threshold;

  /// How much of the image was judged to be ink, 0-1.
  ///
  /// A signature is a few percent of its frame. A very high value means the
  /// photograph was too dark or too shadowed to separate, and the caller
  /// should say so rather than insert a black rectangle into a document.
  final double inkFraction;

  /// Whether the result is worth using.
  ///
  /// The bounds are deliberately wide: this rejects the clearly-broken - a
  /// blank sheet, or a photograph so dark that everything reads as ink - and
  /// leaves everything else to the user's eye, which is better at this than a
  /// number is.
  bool get isUsable => inkFraction > 0.0005 && inkFraction < 0.6;
}

/// Makes the paper transparent in [rgba], leaving the ink.
///
/// [softness] is how many luminance levels the edge fades over. A hard cut
/// produces visibly jagged strokes at the size a signature is drawn; fading
/// across a narrow band keeps the pen's edge smooth without smearing it.
InkExtraction removeBackground(
  List<int> rgba,
  int width,
  int height, {
  int softness = 24,
}) {
  if (rgba.length != width * height * 4) {
    throw ArgumentError.value(
      rgba.length,
      'rgba',
      'expected ${width * height * 4} bytes for ${width}x$height',
    );
  }

  final histogram = List<int>.filled(256, 0);
  final luminance = List<int>.filled(width * height, 0);

  for (var p = 0; p < width * height; p++) {
    // Rec. 601 luma. Green dominates perceived brightness, so a plain average
    // would read blue ink as lighter than it looks.
    final l =
        (rgba[p * 4] * 299 + rgba[p * 4 + 1] * 587 + rgba[p * 4 + 2] * 114) ~/
        1000;
    luminance[p] = l;
    histogram[l]++;
  }

  final threshold = _otsu(histogram, width * height);

  var ink = 0;
  final out = List<int>.of(rgba);

  for (var p = 0; p < width * height; p++) {
    final l = luminance[p];

    // Fully ink below the band, fully paper above it, a ramp between.
    final alpha = l <= threshold - softness
        ? 255
        : l >= threshold + softness
        ? 0
        : (255 * (threshold + softness - l) / (2 * softness)).round();

    out[p * 4 + 3] = alpha;
    if (alpha > 127) ink++;
  }

  return InkExtraction(
    rgba: out,
    threshold: threshold,
    inkFraction: ink / (width * height),
  );
}

/// Otsu's method: the threshold that maximises between-class variance.
///
/// One pass over 256 bins, no iteration to convergence and no parameters, so
/// the same photograph always yields the same result.
///
/// Where several thresholds tie - which happens whenever the image is close to
/// two tones, exactly the case a scanned signature approaches - the MIDPOINT of
/// the tied range is taken. Taking the first, as the textbook loop does, puts
/// the threshold on the darker tone itself, and the soft edge then fades the
/// ink instead of the paper.
int _otsu(List<int> histogram, int total) {
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * histogram[i];
  }

  var sumBackground = 0.0;
  var weightBackground = 0;
  var best = 0.0;
  var first = 128;
  var last = 128;

  for (var t = 0; t < 256; t++) {
    weightBackground += histogram[t];
    if (weightBackground == 0) continue;

    final weightForeground = total - weightBackground;
    if (weightForeground == 0) break;

    sumBackground += t * histogram[t];

    final meanBackground = sumBackground / weightBackground;
    final meanForeground = (sum - sumBackground) / weightForeground;
    final variance =
        weightBackground *
        weightForeground *
        math.pow(meanBackground - meanForeground, 2);

    if (variance > best) {
      best = variance.toDouble();
      first = last = t;
    } else if (variance == best) {
      last = t;
    }
  }

  return (first + last) ~/ 2;
}
