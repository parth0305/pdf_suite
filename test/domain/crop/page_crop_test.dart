import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/crop/page_crop.dart';
import 'package:folio/domain/engine/pdf_types.dart';

const a4 = TextRect(left: 0, bottom: 0, right: 595, top: 842);

/// A white page with a black rectangle at [left]..[right] x [top]..[bottom]
/// measured from the TOP, the way a raster is.
Uint8List painted({
  required int width,
  required int height,
  int left = 0,
  int top = 0,
  int right = -1,
  int bottom = -1,
}) {
  final px = Uint8List(width * height * 4)
    ..fillRange(0, width * height * 4, 255);

  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      final p = (y * width + x) * 4;
      px[p] = 0;
      px[p + 1] = 0;
      px[p + 2] = 0;
    }
  }

  return px;
}

void main() {
  group('croppedBox', () {
    test('trims each side by its own margin', () {
      final box = croppedBox(
        a4,
        const PageMargins(left: 10, bottom: 20, right: 30, top: 40),
      )!;

      expect(box.left, 10);
      expect(box.bottom, 20);
      expect(box.right, 565);
      expect(box.top, 802);
    });

    test('a trim that leaves nothing is refused', () {
      expect(croppedBox(a4, const PageMargins(left: 300, right: 300)), isNull);
    });

    // ISO 32000-1 §14.11.2. A 2-point page is not a crop anyone wanted.
    test('a page below the smallest legal size is refused', () {
      expect(croppedBox(a4, const PageMargins(top: 840)), isNull);
    });
  });

  group('rotation', () {
    // /Rotate 90 displays the page turned clockwise, so the edge the reader
    // calls the top is the /MediaBox left edge.
    test('a quarter turn moves the trim to the left edge', () {
      final m = const PageMargins(top: 50).unrotated(90);

      expect(m.left, 50);
      expect(m.top, 0);
      expect(m.bottom, 0);
      expect(m.right, 0);
    });

    test('three quarter turns move it to the right edge', () {
      expect(const PageMargins(top: 50).unrotated(270).right, 50);
    });

    test('a half turn swaps top with bottom', () {
      expect(const PageMargins(top: 50).unrotated(180).bottom, 50);
    });

    test('no rotation leaves the trim alone', () {
      expect(const PageMargins(top: 50).unrotated(0).top, 50);
    });
  });

  group('union', () {
    test('keeps the smaller margin, which is the safe one', () {
      final m = const PageMargins(
        left: 10,
        top: 40,
      ).union(const PageMargins(left: 30, top: 5));

      expect(m.left, 10);
      expect(m.top, 5);
    });
  });

  group('intersection', () {
    test('clips a box to the crop', () {
      final box = intersection(
        const TextRect(left: 0, bottom: 0, right: 100, top: 100),
        const TextRect(left: 20, bottom: 20, right: 200, top: 200),
      )!;

      expect(box.left, 20);
      expect(box.right, 100);
    });

    test('boxes that miss each other have no intersection', () {
      expect(
        intersection(
          const TextRect(left: 0, bottom: 0, right: 10, top: 10),
          const TextRect(left: 50, bottom: 50, right: 60, top: 60),
        ),
        isNull,
      );
    });
  });

  group('detectContentMargins', () {
    test('finds the ink and leaves padding around it', () {
      // 100x100 px over a 100x100 pt page: one pixel is one point.
      final margins = detectContentMargins(
        painted(
          width: 100,
          height: 100,
          left: 30,
          right: 70,
          top: 20,
          bottom: 80,
        ),
        widthPx: 100,
        heightPx: 100,
        visible: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
        padding: 0,
      );

      expect(margins.left, closeTo(30, 0.5));
      expect(margins.right, closeTo(29, 0.5));
      expect(margins.top, closeTo(20, 0.5));
      expect(margins.bottom, closeTo(19, 0.5));
    });

    test('padding is kept back from the ink', () {
      final margins = detectContentMargins(
        painted(
          width: 100,
          height: 100,
          left: 30,
          right: 70,
          top: 20,
          bottom: 80,
        ),
        widthPx: 100,
        heightPx: 100,
        visible: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
        padding: 6,
      );

      expect(margins.left, closeTo(24, 0.5));
    });

    // The raster's first row is the top of the page and PDF's y grows upward.
    // Getting this backwards trims the mirror image of the margin, which still
    // looks like a crop.
    test(
      'ink near the top gives a small top margin, not a small bottom one',
      () {
        final margins = detectContentMargins(
          painted(
            width: 100,
            height: 100,
            left: 0,
            right: 99,
            top: 2,
            bottom: 8,
          ),
          widthPx: 100,
          heightPx: 100,
          visible: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
          padding: 0,
        );

        expect(margins.top, lessThan(5));
        expect(margins.bottom, greaterThan(80));
      },
    );

    test('pixels are converted through the page size, not assumed 1:1', () {
      // 200 px across a 100 pt page: ink starting at pixel 60 is at 30 pt.
      final margins = detectContentMargins(
        painted(
          width: 200,
          height: 200,
          left: 60,
          right: 140,
          top: 20,
          bottom: 180,
        ),
        widthPx: 200,
        heightPx: 200,
        visible: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
        padding: 0,
      );

      expect(margins.left, closeTo(30, 0.5));
    });

    test('a blank page has nothing to trim', () {
      final margins = detectContentMargins(
        painted(width: 50, height: 50),
        widthPx: 50,
        heightPx: 50,
        visible: const TextRect(left: 0, bottom: 0, right: 50, top: 50),
      );

      expect(margins.isNothing, isTrue);
    });

    // Blue ink on grey paper is darker than the paper but brighter than its
    // own average, which is how a plain average inverts the detection.
    test('coloured ink counts as ink', () {
      final px = painted(width: 20, height: 20);
      for (var y = 5; y < 15; y++) {
        for (var x = 5; x < 15; x++) {
          final p = (y * 20 + x) * 4;
          px[p] = 200; // B
          px[p + 1] = 30; // G
          px[p + 2] = 30; // R
        }
      }

      final margins = detectContentMargins(
        px,
        widthPx: 20,
        heightPx: 20,
        visible: const TextRect(left: 0, bottom: 0, right: 20, top: 20),
        padding: 0,
      );

      expect(margins.left, closeTo(5, 0.5));
    });

    // A scan's background is grey, not white. Measuring against white calls
    // the whole page ink and finds nothing to trim.
    test("ink is measured against the page's own paper", () {
      final px = painted(width: 100, height: 100)
        ..fillRange(0, 100 * 100 * 4, 210);
      for (var y = 40; y < 60; y++) {
        for (var x = 40; x < 60; x++) {
          final p = (y * 100 + x) * 4;
          px[p] = 0;
          px[p + 1] = 0;
          px[p + 2] = 0;
        }
      }

      final margins = detectContentMargins(
        px,
        widthPx: 100,
        heightPx: 100,
        visible: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
        padding: 0,
      );

      expect(margins.left, closeTo(40, 0.5));
      expect(margins.top, closeTo(40, 0.5));
    });

    // A scan's aged edge is a pale yellow band. A plain average reads it as
    // 25 levels below white and calls it content, so the crop finds no margin
    // to trim on the very side that needed trimming.
    test('a pale tint is paper, not content', () {
      final px = painted(width: 100, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 10; x++) {
          final p = (y * 100 + x) * 4;
          px[p] = 180; // B
          px[p + 1] = 255;
          px[p + 2] = 255;
        }
      }
      for (var y = 40; y < 60; y++) {
        for (var x = 40; x < 60; x++) {
          final p = (y * 100 + x) * 4;
          px[p] = 0;
          px[p + 1] = 0;
          px[p + 2] = 0;
        }
      }

      final margins = detectContentMargins(
        px,
        widthPx: 100,
        heightPx: 100,
        visible: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
        padding: 0,
      );

      expect(margins.left, closeTo(40, 0.5));
    });
  });

  test('millimetres convert to points', () {
    expect(mmToPoints(25.4), closeTo(72, 0.001));
    expect(pointsToMm(72), closeTo(25.4, 0.001));
  });
}
