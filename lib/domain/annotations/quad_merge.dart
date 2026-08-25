import 'package:folio/domain/engine/pdf_types.dart';

/// Half a typical line height. Glyphs on one line vary slightly in baseline and
/// height, so an exact comparison would split a line into one quad per
/// character; anything larger would swallow a genuine line break.
const double _lineTolerance = 6;

/// Collapses per-character rectangles into one quad per line of text.
///
/// `charRects` holds a rectangle per code unit. Emitting those directly would
/// produce hundreds of quads for an ordinary selection - a /QuadPoints array of
/// thousands of numbers - when a highlight only needs one quad per line.
///
/// Input is assumed to be in reading order, which is what `charRects` provides.
List<TextRect> mergeIntoLineQuads(List<TextRect> charRects) {
  if (charRects.isEmpty) return const [];

  final quads = <TextRect>[];
  var left = charRects.first.left;
  var right = charRects.first.right;
  var bottom = charRects.first.bottom;
  var top = charRects.first.top;

  void flush() =>
      quads.add(TextRect(left: left, top: top, right: right, bottom: bottom));

  for (final rect in charRects.skip(1)) {
    // A new line when the baseline moves by more than jitter. y is up, so a
    // later line has a smaller bottom.
    if ((rect.bottom - bottom).abs() > _lineTolerance) {
      flush();
      left = rect.left;
      right = rect.right;
      bottom = rect.bottom;
      top = rect.top;
      continue;
    }

    if (rect.left < left) left = rect.left;
    if (rect.right > right) right = rect.right;
    // The line's box covers its tallest glyph and lowest descender.
    if (rect.top > top) top = rect.top;
    if (rect.bottom < bottom) bottom = rect.bottom;
  }
  flush();

  return quads;
}
