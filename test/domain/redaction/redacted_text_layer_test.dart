import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/redaction/redacted_text_layer.dart';
import 'package:folio/domain/redaction/redaction_box.dart';

/// A character rect one unit wide and ten tall, with its left edge at [left].
TextRect charAt(double left) =>
    TextRect(left: left, right: left + 6, top: 110, bottom: 100);

PageText textOf(String s) => PageText(
  fullText: s,
  charRects: [for (var i = 0; i < s.length; i++) charAt(i * 6.0)],
);

RedactionBox boxOver({
  required double left,
  required double right,
  int page = 0,
}) => RedactionBox(
  pageIndex: page,
  rect: TextRect(left: left, right: right, top: 115, bottom: 95),
);

void main() {
  group('survivingIndices', () {
    test('a character wholly inside a box is dropped', () {
      // 'ABCDEF' -> chars at 0..6, 6..12, 12..18, 18..24, 24..30, 30..36.
      final keep = survivingIndices(textOf('ABCDEF'), [
        boxOver(left: 11, right: 19),
      ], 0);

      expect(keep, isNot(contains(2)), reason: 'C spans 12..18, inside');
    });

    // Half a glyph is often enough to read, and a character the box touches is
    // a character the user meant to remove.
    test('a character overlapping only the box edge is also dropped', () {
      final keep = survivingIndices(
        textOf('ABCDEF'),
        // Covers 15..40, so D (18..24) is inside but C (12..18) only touches.
        [boxOver(left: 15, right: 40)],
        0,
      );

      expect(
        keep,
        isNot(contains(2)),
        reason:
            'C overlaps the box from 15 to 18 - intersection, not '
            'containment',
      );
    });

    test('a character outside every box survives', () {
      final keep = survivingIndices(textOf('ABCDEF'), [
        boxOver(left: 11, right: 19),
      ], 0);

      expect(keep, contains(0));
      expect(keep, contains(5));
    });

    test('a box on another page does not affect this one', () {
      final keep = survivingIndices(textOf('ABCDEF'), [
        boxOver(left: 0, right: 100, page: 1),
      ], 0);

      expect(keep, hasLength(6), reason: 'every character survives');
    });

    test('a box that misses vertically drops nothing', () {
      final keep = survivingIndices(textOf('ABCDEF'), [
        RedactionBox(
          pageIndex: 0,
          // Well above the characters, which sit at 100..110.
          rect: const TextRect(left: 0, right: 100, top: 300, bottom: 200),
        ),
      ], 0);

      expect(keep, hasLength(6));
    });

    test('no boxes keeps everything', () {
      expect(survivingIndices(textOf('ABCDEF'), const [], 0), hasLength(6));
    });
  });
  group('invisibleTextStream', () {
    String streamFor(String content, List<RedactionBox> boxes) {
      final text = textOf(content);
      return invisibleTextStream(text, survivingIndices(text, boxes, 0));
    }

    test('draws in text render mode 3, which is invisible', () {
      expect(streamFor('AB', const []), contains('3 Tr'));
    });

    test('a surviving character is in the stream', () {
      expect(streamFor('AB', const []), contains('(A)'));
      expect(streamFor('AB', const []), contains('(B)'));
    });

    // The whole point: a redacted character must not appear anywhere.
    test('a redacted character is absent', () {
      final stream = streamFor('AB', [boxOver(left: -1, right: 5)]);

      expect(stream, isNot(contains('(A)')));
      expect(stream, contains('(B)'));
    });

    test('each character is positioned at its own rect', () {
      final stream = streamFor('AB', const []);

      // A sits at left 0, B at left 6, both with bottom 100.
      expect(stream, contains('1 0 0 1 0 100 Tm'));
      expect(stream, contains('1 0 0 1 6 100 Tm'));
    });

    test('parentheses and backslashes are escaped', () {
      final text = PageText(
        fullText: r'(\)',
        charRects: [charAt(0), charAt(6), charAt(12)],
      );
      final stream = invisibleTextStream(text, const [0, 1, 2]);

      expect(stream, contains(r'\('));
      expect(stream, contains(r'\)'));
      expect(stream, contains(r'\\'));
    });

    // A standard-14 font with WinAnsiEncoding cannot represent these. They
    // stay visible in the raster; they are simply not searchable. Emitting
    // them anyway would write bytes that mean something else entirely.
    test('a character outside WinAnsi is omitted, not mangled', () {
      final text = PageText(
        fullText: 'A\u4e2dB',
        charRects: [charAt(0), charAt(6), charAt(12)],
      );
      final stream = invisibleTextStream(text, const [0, 1, 2]);

      expect(stream, contains('(A)'));
      expect(stream, contains('(B)'));
      expect(stream, isNot(contains('\u4e2d')));
    });

    test('whitespace is not emitted as a glyph', () {
      final text = PageText(
        fullText: 'A B',
        charRects: [charAt(0), charAt(6), charAt(12)],
      );

      expect(
        RegExp(
          r'Tj',
        ).allMatches(invisibleTextStream(text, const [0, 1, 2])).length,
        2,
        reason: 'a space has no visible glyph and nothing to position',
      );
    });

    test('nothing surviving produces an empty stream', () {
      expect(invisibleTextStream(textOf('AB'), const []), isEmpty);
    });
  });
}
