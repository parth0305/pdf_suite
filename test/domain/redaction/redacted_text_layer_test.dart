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
        const RedactionBox(
          pageIndex: 0,
          // Well above the characters, which sit at 100..110.
          rect: TextRect(left: 0, right: 100, top: 300, bottom: 200),
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

    // One Tj per RUN, not per character: a page whose every glyph is its own
    // text object extracts as 'C o n f i d e n t i a l', which no search
    // matches.
    test('adjacent characters share one run', () {
      final stream = streamFor('AB', const []);

      expect(stream, contains('(AB)'));
      expect(RegExp(r'Tj').allMatches(stream).length, 1);
    });

    // The whole point: a redacted character must not appear anywhere.
    test('a redacted character is absent', () {
      final stream = streamFor('AB', [boxOver(left: -1, right: 5)]);

      expect(stream, isNot(contains('A')));
      expect(stream, contains('(B)'));
    });

    // Without this the halves either side of a redaction would be joined into
    // a word that never existed, and a search for it would hit.
    test('a removed character splits the run', () {
      // 'ABCDE', box over C only (12..18).
      final stream = streamFor('ABCDE', [boxOver(left: 12.5, right: 17.5)]);

      expect(stream, contains('(AB)'));
      expect(stream, contains('(DE)'));
      expect(
        stream,
        isNot(contains('(ABDE)')),
        reason: 'the run must break where the character was removed',
      );
    });

    test('a run is positioned at its first character', () {
      // 'ABCDE' with C removed: the second run starts at D, left 18.
      final stream = streamFor('ABCDE', [boxOver(left: 12.5, right: 17.5)]);

      expect(stream, contains('1 0 0 1 0 100 Tm'));
      expect(stream, contains('1 0 0 1 18 100 Tm'));
    });

    test('a line break ends a run', () {
      const text = PageText(
        fullText: 'A\nB',
        charRects: [
          TextRect(left: 0, right: 6, top: 110, bottom: 100),
          TextRect(left: 6, right: 7, top: 110, bottom: 100),
          TextRect(left: 0, right: 6, top: 90, bottom: 80),
        ],
      );

      expect(
        RegExp(
          r'Tj',
        ).allMatches(invisibleTextStream(text, const [0, 1, 2])).length,
        2,
      );
    });

    // A descender's glyph box sits lower than its neighbours' and a hyphen's
    // sits higher. Splitting runs on that geometry turns 'rupees' into
    // 'ru p ees' and 'REDACT-ME-9931' into 'REDACT - ME - 9931' - measured on
    // a real page, not hypothesised.
    test('a descender does not split a run', () {
      const text = PageText(
        fullText: 'rup',
        charRects: [
          TextRect(left: 0, right: 6, top: 106, bottom: 100),
          TextRect(left: 6, right: 12, top: 106, bottom: 100),
          TextRect(left: 12, right: 18, top: 106, bottom: 94),
        ],
      );

      expect(invisibleTextStream(text, const [0, 1, 2]), contains('(rup)'));
    });

    test('a hyphen does not split a run', () {
      const text = PageText(
        fullText: 'A-B',
        charRects: [
          TextRect(left: 0, right: 6, top: 110, bottom: 100),
          TextRect(left: 6, right: 10, top: 106, bottom: 104),
          TextRect(left: 10, right: 16, top: 110, bottom: 100),
        ],
      );

      expect(invisibleTextStream(text, const [0, 1, 2]), contains('(A-B)'));
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
