import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';

const quad = TextRect(left: 60, top: 712, right: 120, bottom: 700);

TextMarkup of(MarkupKind kind) =>
    TextMarkup(kind: kind, pageIndex: 0, quads: const [quad]);

void main() {
  group('appearanceStream', () {
    test('highlight fills the quad', () {
      final s = appearanceStream(of(MarkupKind.highlight));
      expect(s, contains('re'), reason: 'a rectangle path');
      expect(s, contains('f'), reason: 'filled');
      expect(s, contains('60'));
    });

    // Without Multiply, a highlight paints over the text and hides it.
    test('highlight uses the Multiply blend mode', () {
      expect(appearanceStream(of(MarkupKind.highlight)), contains('/GSHL gs'));
    });

    test('underline strokes a line at the bottom of the quad', () {
      final s = appearanceStream(of(MarkupKind.underline));
      expect(s, contains('S'), reason: 'stroked, not filled');
      expect(s, contains('700'), reason: 'at the quad bottom');
    });

    test('strikeout strokes a line through the middle of the quad', () {
      final s = appearanceStream(of(MarkupKind.strikeOut));
      expect(s, contains('S'));
      expect(s, contains('706'), reason: 'midpoint of 700..712');
    });

    test('multiple quads each produce their own path', () {
      const second = TextRect(left: 60, top: 690, right: 200, bottom: 678);
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [quad, second],
      );
      expect('re'.allMatches(appearanceStream(markup)).length, 2);
    });
  });

  group('appearanceDict', () {
    test('is a form XObject with a BBox spanning the markup', () {
      final d = appearanceDict(of(MarkupKind.highlight), 42);

      expect(d, contains('/Type /XObject'));
      expect(d, contains('/Subtype /Form'));
      expect(d, contains('/BBox [60 700 120 712]'));
      expect(d, contains('/Length 42'));
    });

    test('highlight declares the Multiply graphics state', () {
      final d = appearanceDict(of(MarkupKind.highlight), 10);
      expect(d, contains('/ExtGState'));
      expect(d, contains('/Multiply'));
    });

    test('underline needs no graphics state', () {
      expect(
        appearanceDict(of(MarkupKind.underline), 10),
        isNot(contains('/Multiply')),
      );
    });
  });
}
