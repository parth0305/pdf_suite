import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/quad_merge.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// One character box on a line whose baseline sits at [bottom].
TextRect ch(
  double left,
  double bottom, {
  double width = 7,
  double height = 12,
}) => TextRect(
  left: left,
  right: left + width,
  bottom: bottom,
  top: bottom + height,
);

void main() {
  group('mergeIntoLineQuads', () {
    test('an empty selection yields no quads', () {
      expect(mergeIntoLineQuads(const []), isEmpty);
    });

    // Without merging, a 40-character selection would emit 40 quads and a
    // /QuadPoints array of 320 numbers.
    test('characters on one line collapse into a single quad', () {
      final rects = [for (var i = 0; i < 5; i++) ch(60 + i * 7, 700)];
      final quads = mergeIntoLineQuads(rects);

      expect(quads, hasLength(1));
      expect(quads.single.left, 60);
      expect(quads.single.right, 60 + 5 * 7);
      expect(quads.single.bottom, 700);
      expect(quads.single.top, 712);
    });

    test('two lines produce two quads', () {
      final rects = [
        for (var i = 0; i < 3; i++) ch(60 + i * 7, 700),
        for (var i = 0; i < 4; i++) ch(60 + i * 7, 680),
      ];
      final quads = mergeIntoLineQuads(rects);

      expect(quads, hasLength(2));
      expect(quads[0].bottom, 700);
      expect(quads[1].bottom, 680);
    });

    // Glyphs on one line vary slightly in height and baseline; a strict
    // equality check would split a line into many quads.
    test('minor baseline jitter stays on one line', () {
      final rects = [ch(60, 700), ch(67, 700.4), ch(74, 699.6), ch(81, 700)];
      expect(mergeIntoLineQuads(rects), hasLength(1));
    });

    test('a genuine line break is not absorbed by the tolerance', () {
      final rects = [ch(60, 700), ch(67, 700), ch(60, 686)];
      expect(mergeIntoLineQuads(rects), hasLength(2));
    });

    test('the quad spans the full extent of its line', () {
      final rects = [ch(60, 700), ch(200, 700, width: 20)];
      final quad = mergeIntoLineQuads(rects).single;

      expect(quad.left, 60);
      expect(quad.right, 220);
    });

    test('a line quad uses the tallest glyph on that line', () {
      final rects = [ch(60, 700, height: 12), ch(67, 700, height: 16)];
      expect(mergeIntoLineQuads(rects).single.top, 716);
    });

    // Quad order does not affect rendering - each quad stands alone - so the
    // function preserves input order rather than sorting. charRects already
    // arrive in reading order.
    test('input order is preserved', () {
      final rects = [ch(60, 680), ch(60, 700)];
      final quads = mergeIntoLineQuads(rects);

      expect(quads.first.bottom, 680);
      expect(quads.last.bottom, 700);
    });

    test('a single character yields one quad', () {
      expect(mergeIntoLineQuads([ch(60, 700)]), hasLength(1));
    });
  });
}
