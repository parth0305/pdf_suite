import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/scanner/pdf_image_document.dart';
import 'package:folio/domain/scanner/scanned_page.dart';

import 'jpeg_fixtures.dart';

String textOf(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

void main() {
  test('one page per image, in the order given', () {
    final out = textOf(
      buildScannedDocument([
        ScannedPage(kColourJpeg),
        ScannedPage(kGrayJpeg),
        ScannedPage(kColourJpeg),
      ]),
    );

    expect(RegExp(r'/Type /Page\b').allMatches(out).length, 3);
    expect(out, contains('/Count 3'));
  });

  // Order is not decorative: a scan whose pages arrive shuffled is unusable,
  // and every page dictionary otherwise looks identical.
  test('the page tree lists pages in capture order', () {
    final out = textOf(
      buildScannedDocument([ScannedPage(kColourJpeg), ScannedPage(kGrayJpeg)]),
    );

    final kids = RegExp(r'/Kids \[([^\]]*)\]').firstMatch(out)!.group(1)!;
    final numbers = RegExp(
      r'(\d+) 0 R',
    ).allMatches(kids).map((m) => int.parse(m.group(1)!)).toList();

    expect(numbers, [5, 8], reason: 'first captured page comes first');

    // And the FIRST page must reference the colour image, not the grey one.
    final firstPage = RegExp(
      r'5 0 obj(.*?)endobj',
      dotAll: true,
    ).firstMatch(out)!.group(1)!;
    final imageRef = int.parse(
      RegExp(r'/ScIm0 (\d+) 0 R').firstMatch(firstPage)!.group(1)!,
    );
    final image = RegExp(
      '$imageRef 0 obj(.*?)stream',
      dotAll: true,
    ).firstMatch(out)!.group(1)!;

    expect(image, contains('/DeviceRGB'));
  });

  group('the image dictionary', () {
    test('declares DCTDecode and the JPEG byte count exactly', () {
      final out = textOf(buildScannedDocument([ScannedPage(kColourJpeg)]));

      expect(out, contains('/Filter /DCTDecode'));
      expect(
        out,
        contains('/Length ${kColourJpeg.length}'),
        reason: 'the JPEG is embedded untouched',
      );
    });

    test('carries the real pixel dimensions', () {
      final out = textOf(buildScannedDocument([ScannedPage(kColourJpeg)]));

      expect(out, contains('/Width 64'));
      expect(out, contains('/Height 64'));
    });

    test('a grayscale page declares DeviceGray', () {
      final out = textOf(buildScannedDocument([ScannedPage(kGrayJpeg)]));

      expect(out, contains('/DeviceGray'));
      expect(out, isNot(contains('/DeviceRGB')));
    });

    test('the JPEG bytes survive into the file unchanged', () {
      final built = buildScannedDocument([ScannedPage(kColourJpeg)]);
      final marker = latin1.encode('/Filter /DCTDecode >>\nstream\n');

      var at = -1;
      for (var i = 0; i + marker.length < built.length; i++) {
        if (List.of(built.skip(i).take(marker.length)).toString() ==
            marker.toString()) {
          at = i + marker.length;
          break;
        }
      }
      expect(at, greaterThan(0), reason: 'the stream must be findable');

      expect(built.sublist(at, at + kColourJpeg.length), kColourJpeg);
    });
  });

  group('page geometry', () {
    test('a square image is centred on A4', () {
      final out = textOf(buildScannedDocument([ScannedPage(kColourJpeg)]));

      // 64x64 fitted to 595x842 scales by 595/64, giving 595x595, so it is
      // centred vertically with (842-595)/2 = 123.5 above and below.
      expect(out, contains('595 0 0 595 0 123.50 cm'));
    });

    test('every page is A4', () {
      final out = textOf(buildScannedDocument([ScannedPage(kColourJpeg)]));

      expect(out, contains('/MediaBox [0 0 595 842]'));
    });
  });

  test('the xref offsets point at the objects', () {
    final built = buildScannedDocument([ScannedPage(kColourJpeg)]);
    final out = textOf(built);

    final table = out.substring(out.lastIndexOf('\nxref\n') + 6);
    final rows = RegExp(
      r'^(\d{10}) \d{5} n',
      multiLine: true,
    ).allMatches(table).map((m) => int.parse(m.group(1)!)).toList();

    expect(rows, hasLength(greaterThan(2)));
    for (var i = 0; i < rows.length; i++) {
      expect(
        out.startsWith('${i + 1} 0 obj', rows[i]),
        isTrue,
        reason: 'offset ${rows[i]} must land on object ${i + 1}',
      );
    }
  });

  test('an empty scan is refused rather than producing a blank file', () {
    expect(() => buildScannedDocument(const []), throwsArgumentError);
  });
}
