import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/signature/background_removal.dart';

/// A [w]x[h] image of [paper], with [ink] painted where [isInk] says so.
List<int> image(
  int w,
  int h, {
  required int paper,
  required int ink,
  required bool Function(int x, int y) isInk,
}) {
  final out = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = isInk(x, y) ? ink : paper;
      out.addAll([v, v, v, 255]);
    }
  }
  return out;
}

int alphaAt(List<int> rgba, int w, int x, int y) => rgba[(y * w + x) * 4 + 3];

void main() {
  group('separating ink from paper', () {
    test('paper becomes transparent and ink stays opaque', () {
      // A dark stroke down the middle of a light sheet.
      final input = image(
        40,
        40,
        paper: 240,
        ink: 20,
        isInk: (x, y) => x >= 18 && x <= 21,
      );

      final result = removeBackground(input, 40, 40);

      expect(alphaAt(result.rgba, 40, 20, 20), 255, reason: 'on the stroke');
      expect(alphaAt(result.rgba, 40, 2, 20), 0, reason: 'on the paper');
    });

    // Keeping the pen's own colour is what makes the result look like the
    // signature rather than a traced copy of it.
    test('the ink keeps its colour', () {
      final input = <int>[];
      for (var i = 0; i < 16; i++) {
        // Blue pen on white.
        input.addAll(i < 4 ? [20, 40, 160, 255] : [245, 245, 245, 255]);
      }

      final result = removeBackground(input, 4, 4);

      expect(result.rgba[0], 20);
      expect(result.rgba[1], 40);
      expect(result.rgba[2], 160);
    });

    // Rec. 601 weights green far above blue. Pure blue ink LOOKS dark but its
    // plain RGB average does not: (0,0,255) averages 85 while its luma is 29.
    // On mid-grey paper the average makes the ink read as LIGHTER than the
    // page, and the extraction comes out inverted - paper kept, ink dropped.
    test('blue ink on grey paper is not inverted', () {
      final input = <int>[];
      for (var i = 0; i < 64; i++) {
        input.addAll(i < 8 ? [0, 0, 255, 255] : [70, 70, 70, 255]);
      }

      final result = removeBackground(input, 8, 8, softness: 0);

      expect(result.rgba[3], 255, reason: 'the blue ink is kept');
      expect(result.rgba[8 * 4 + 3], 0, reason: 'the grey paper is dropped');
    });

    test('the threshold lands between the two tones', () {
      final result = removeBackground(
        image(20, 20, paper: 230, ink: 30, isInk: (x, y) => x < 4),
        20,
        20,
      );

      expect(result.threshold, greaterThan(30));
      expect(result.threshold, lessThan(230));
    });

    // A hard cut is visibly jagged at the size a signature is drawn.
    test('the edge fades rather than stepping', () {
      // A gradient, so there are intermediate tones to fade across.
      final input = <int>[];
      for (var x = 0; x < 256; x++) {
        input.addAll([x, x, x, 255]);
      }

      final result = removeBackground(input, 256, 1, softness: 24);
      final alphas = [for (var x = 0; x < 256; x++) result.rgba[x * 4 + 3]];
      final partial = alphas.where((a) => a > 0 && a < 255).length;

      expect(partial, greaterThan(4), reason: 'a ramp, not a cliff');
    });

    test('softness zero gives a hard edge', () {
      final input = <int>[];
      for (var x = 0; x < 256; x++) {
        input.addAll([x, x, x, 255]);
      }

      final result = removeBackground(input, 256, 1, softness: 0);
      final partial = [
        for (var x = 0; x < 256; x++) result.rgba[x * 4 + 3],
      ].where((a) => a > 0 && a < 255).length;

      expect(partial, 0);
    });
  });

  group('judging whether the photograph is usable', () {
    test('a normal signature is usable', () {
      final result = removeBackground(
        image(100, 100, paper: 235, ink: 25, isInk: (x, y) => y > 45 && y < 52),
        100,
        100,
      );

      expect(result.isUsable, isTrue);
      expect(result.inkFraction, greaterThan(0.0));
    });

    // A photograph so dark that everything reads as ink would insert a black
    // rectangle into someone's document.
    test('an almost entirely dark photograph is refused', () {
      final result = removeBackground(
        image(50, 50, paper: 30, ink: 10, isInk: (x, y) => y < 45),
        50,
        50,
      );

      expect(result.isUsable, isFalse);
    });

    test('a blank sheet is refused', () {
      final result = removeBackground(
        image(50, 50, paper: 250, ink: 250, isInk: (x, y) => false),
        50,
        50,
      );

      expect(result.isUsable, isFalse, reason: 'there is no ink to extract');
    });
  });

  // RangeError EXTENDS ArgumentError in Dart, so `throwsArgumentError` also
  // matches an out-of-bounds read - which is exactly what removing the guard
  // produces. The message is what tells the two apart.
  test('a wrongly sized buffer is refused rather than read past its end', () {
    expect(
      () => removeBackground(List<int>.filled(10, 0), 40, 40),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('expected'),
        ),
      ),
    );
  });
}
