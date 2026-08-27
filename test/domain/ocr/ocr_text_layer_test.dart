import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/ocr/ocr_text_layer.dart';
import 'package:folio/domain/ocr/ocr_word.dart';

/// A 1000x2000 pixel image placed on a 500x1000 point page at the origin, so
/// the scale is exactly 0.5 and every expected number is checkable by hand.
String layerFor(OcrPage page, {double offsetX = 0, double offsetY = 0}) =>
    ocrTextLayer(
      page: page,
      imageWidth: 1000,
      imageHeight: 2000,
      pageWidth: 500,
      pageHeight: 1000,
      offsetX: offsetX,
      offsetY: offsetY,
    );

const word = OcrWord(
  text: 'Invoice',
  left: 100,
  top: 200,
  right: 300,
  bottom: 260,
);

void main() {
  group('positioned', () {
    test('paints nothing but stays extractable', () {
      final layer = layerFor(const OcrPage(lines: [], words: [word]));

      expect(layer, contains('3 Tr'));
      expect(layer, contains('(Invoice)'));
    });

    // Image pixels count down from the top; PDF points count up from the
    // bottom. Getting this wrong puts every word on the mirror image of its
    // line, which still looks like a working text layer.
    test('the vertical axis is flipped', () {
      final layer = layerFor(const OcrPage(lines: [], words: [word]));

      // x = 100 * 0.5 = 50. y = (2000 - 260) * 0.5 = 870.
      expect(layer, contains('1 0 0 1 50 870 Tm'));
    });

    test('the font size follows the word height', () {
      final layer = layerFor(const OcrPage(lines: [], words: [word]));

      // (260 - 200) * 0.5 = 30.
      expect(layer, contains('/OcF1 30 Tf'));
    });

    test('the image offset on the page is added', () {
      final layer = layerFor(
        const OcrPage(lines: [], words: [word]),
        offsetX: 40,
        offsetY: 10,
      );

      expect(layer, contains('1 0 0 1 90 880 Tm'));
    });

    test('one Tj per word', () {
      final layer = layerFor(
        const OcrPage(
          lines: [],
          words: [
            word,
            OcrWord(
              text: 'Total',
              left: 400,
              top: 200,
              right: 600,
              bottom: 260,
            ),
          ],
        ),
      );

      expect(RegExp(r'Tj').allMatches(layer).length, 2);
    });

    test('parentheses and backslashes are escaped', () {
      final layer = layerFor(
        const OcrPage(
          lines: [],
          words: [
            OcrWord(text: r'a(b)\c', left: 0, top: 0, right: 10, bottom: 10),
          ],
        ),
      );

      expect(layer, contains(r'\('));
      expect(layer, contains(r'\)'));
      expect(layer, contains(r'\\'));
    });

    // Same rule redaction uses: a non-embedded standard-14 font cannot carry
    // these, and emitting the byte would write a different character.
    test('characters outside WinAnsi are dropped, not mangled', () {
      final layer = layerFor(
        const OcrPage(
          lines: [],
          words: [OcrWord(text: 'A中B', left: 0, top: 0, right: 10, bottom: 10)],
        ),
      );

      expect(layer, contains('(AB)'));
      expect(layer, isNot(contains('中')));
    });

    test('a word that is entirely unrepresentable is skipped', () {
      final layer = layerFor(
        const OcrPage(
          lines: [],
          words: [OcrWord(text: '中文', left: 0, top: 0, right: 10, bottom: 10)],
        ),
      );

      expect(layer, isEmpty, reason: 'an empty () Tj is noise, not text');
    });
  });

  group('approximate fallback', () {
    const page = OcrPage(lines: ['First line', 'Second line', 'Third line']);

    test('is used when there are no word boxes', () {
      final layer = layerFor(page);

      expect(layer, contains('(First line)'));
      expect(RegExp(r'Tj').allMatches(layer).length, 3);
    });

    // Reading order has to survive even when position does not: text extracted
    // in the wrong order is worse than text with imprecise boxes.
    test('the first line sits above the last', () {
      final layer = layerFor(page);

      // Each Tj is on its own output line, so find the line carrying the
      // text and read y out of its own Tm.
      double yOf(String text) {
        final row = layer.split('\n').firstWhere((l) => l.contains('($text)'));
        return double.parse(
          RegExp(r'1 0 0 1 [\d.]+ ([\d.]+) Tm').firstMatch(row)!.group(1)!,
        );
      }

      expect(yOf('First line'), greaterThan(yOf('Third line')));
    });

    test('every line is on the page', () {
      final layer = layerFor(page);

      for (final m in RegExp(r'1 0 0 1 [\d.]+ ([\d.]+) Tm').allMatches(layer)) {
        final y = double.parse(m.group(1)!);
        expect(y, greaterThan(0));
        expect(y, lessThan(1000));
      }
    });

    test('an empty page produces an empty layer', () {
      expect(layerFor(const OcrPage(lines: [])), isEmpty);
    });
  });
}
