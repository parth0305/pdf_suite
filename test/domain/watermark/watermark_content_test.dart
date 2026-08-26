import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'package:folio/domain/watermark/watermark_content.dart';

const a4 = TextRect(left: 0, bottom: 0, right: 595, top: 842);
const draft = Watermark(text: 'DRAFT');

void main() {
  group('the stream restores what it found', () {
    // Our stream runs after the page's own content. An unbalanced stream
    // leaks graphics state into everything appended after it.
    test('is q/Q balanced', () {
      final s = watermarkContentStream(draft, mediaBox: a4);

      expect(RegExp(r'^q$', multiLine: true).allMatches(s).length, 1);
      expect(RegExp(r'^Q$', multiLine: true).allMatches(s).length, 1);
      expect(s.trimLeft().startsWith('q'), isTrue);
      expect(s.trimRight().endsWith('Q'), isTrue);
    });
  });

  group('what it draws', () {
    test('draws the text', () {
      expect(watermarkContentStream(draft, mediaBox: a4), contains('(DRAFT)'));
      expect(watermarkContentStream(draft, mediaBox: a4), contains('Tj'));
    });

    test('uses the named font resource', () {
      expect(watermarkContentStream(draft, mediaBox: a4), contains('/WMF1'));
    });

    // Opacity belongs in an ExtGState. Faking it with a pale fill colour
    // would look wrong over dark content and could not be undone by a viewer.
    test('applies opacity through the ExtGState, not the fill colour', () {
      final s = watermarkContentStream(draft, mediaBox: a4);

      expect(s, contains('/WMGS gs'));
      expect(watermarkExtGState(draft), contains('/ca 0.3'));
      expect(watermarkExtGState(draft), contains('/CA 0.3'));
    });

    test('escapes parentheses in the text', () {
      const tricky = Watermark(text: 'see (b)');
      expect(
        watermarkContentStream(tricky, mediaBox: a4),
        contains(r'(see \(b\))'),
      );
    });
  });

  group('placement', () {
    test('rotates about the page centre when diagonal', () {
      final s = watermarkContentStream(draft, mediaBox: a4);

      expect(s, contains('297.5 421 cm'));
      expect(s, contains('cm'));
    });

    test('emits no rotation when horizontal', () {
      const flat = Watermark(
        text: 'DRAFT',
        rotation: WatermarkRotation.horizontal,
      );
      final s = watermarkContentStream(flat, mediaBox: a4);

      // One cm for the centring translate, none for a rotation.
      expect(RegExp(r'\bcm\b').allMatches(s).length, 1);
    });

    // A page is not always A4, and a watermark centred on the wrong size
    // lands off the paper.
    test('centres on the page it is given', () {
      const wide = TextRect(left: 0, bottom: 0, right: 1000, top: 500);
      final s = watermarkContentStream(draft, mediaBox: wide);

      expect(s, contains('500 250 cm'));
    });

    test('honours a non-zero MediaBox origin', () {
      const offset = TextRect(left: 100, bottom: 100, right: 700, top: 900);
      final s = watermarkContentStream(draft, mediaBox: offset);

      expect(s, contains('400 500 cm'));
    });
  });

  group('style', () {
    test('emits the colour as a fill colour', () {
      const red = Watermark(text: 'DRAFT', colorArgb: 0xFFFF0000);
      expect(watermarkContentStream(red, mediaBox: a4), contains('1 0 0 rg'));
    });

    test('emits the font size', () {
      const big = Watermark(text: 'DRAFT', fontSizePt: 72);
      expect(
        watermarkContentStream(big, mediaBox: a4),
        contains('/WMF1 72 Tf'),
      );
    });
  });
}
