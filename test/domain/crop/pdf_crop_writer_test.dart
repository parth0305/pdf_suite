import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/crop/page_crop.dart';
import 'package:folio/domain/crop/pdf_crop_writer.dart';

Uint8List document({
  String pageOne = '/Type /Page /Parent 2 0 R /Contents 4 0 R',
  String pagesNode =
      '/Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
      '/MediaBox [0 0 595 842]',
}) => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< $pagesNode >>\nendobj\n'
    '3 0 obj\n<< $pageOne >>\nendobj\n'
    '4 0 obj\n<< /Length 9 >>\nstream\nPAGE-ONE!\nendstream\nendobj\n'
    '5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>\nendobj\n'
    '6 0 obj\n<< /Length 9 >>\nstream\nPAGE-TWO!\nendstream\nendobj\n'
    'xref\n0 7\n0000000000 65535 f \n'
    'trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

String cropped(
  PageMargins margins, {
  String? pageOne,
  String? pagesNode,
}) => latin1.decode(
  writeCroppedPages(
    document(
      pageOne: pageOne ?? '/Type /Page /Parent 2 0 R /Contents 4 0 R',
      pagesNode:
          pagesNode ??
          '/Type /Pages /Kids [3 0 R 5 0 R] /Count 2 /MediaBox [0 0 595 842]',
    ),
    margins,
  ),
  allowInvalid: true,
);

/// The LAST definition of an object, which is what a reader walking the
/// trailer chain backwards sees. The negative lookbehind keeps `3 0 obj` from
/// matching inside `13 0 obj`.
String objectBody(String out, int number) => RegExp(
  '(?<![0-9])$number 0 obj(.*?)endobj',
  dotAll: true,
).allMatches(out).last.group(1)!;

List<double> boxIn(String dict, String name) =>
    RegExp(
          '/$name'
          r'\s*\[([^\]]*)\]',
        )
        .firstMatch(dict)!
        .group(1)!
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .map(double.parse)
        .toList();

void main() {
  test('the page gets a crop box trimmed by the margins', () {
    final page = objectBody(
      cropped(const PageMargins(left: 10, bottom: 20, right: 30, top: 40)),
      3,
    );

    expect(boxIn(page, 'CropBox'), [10, 20, 565, 802]);
  });

  // Setting only /CropBox loses the crop the first time something reads
  // /MediaBox instead - printing, most often.
  test('the media box is trimmed too', () {
    final page = objectBody(cropped(const PageMargins(left: 10)), 3);

    expect(boxIn(page, 'MediaBox'), [10, 0, 595, 842]);
  });

  test('every page is cropped, not just the first', () {
    final out = cropped(const PageMargins(left: 10));

    expect(boxIn(objectBody(out, 5), 'CropBox'), [10, 0, 595, 842]);
  });

  test('the original bytes are still there, untouched', () {
    final out = cropped(const PageMargins(left: 10));

    expect(out, contains('PAGE-ONE!'));
    expect(out.indexOf('%PDF-1.4'), 0);
  });

  test('the page keeps everything else in its dictionary', () {
    final page = objectBody(cropped(const PageMargins(left: 10)), 3);

    expect(page, contains('/Contents 4 0 R'));
    expect(page, contains('/Parent 2 0 R'));
  });

  test('an existing crop box is replaced, not duplicated', () {
    final out = cropped(
      const PageMargins(left: 10),
      pageOne:
          '/Type /Page /Parent 2 0 R /Contents 4 0 R '
          '/CropBox [20 20 500 700]',
    );
    final page = objectBody(out, 3);

    expect('/CropBox'.allMatches(page).length, 1);
  });

  // Cropping an already-cropped page has to start from what is visible. From
  // /MediaBox, a second crop would push the box back OUT, undoing the first.
  test('cropping again trims from the visible box', () {
    final out = cropped(
      const PageMargins(left: 10),
      pageOne:
          '/Type /Page /Parent 2 0 R /Contents 4 0 R '
          '/CropBox [20 20 500 700]',
    );

    expect(boxIn(objectBody(out, 3), 'CropBox'), [30, 20, 500, 700]);
  });

  test('a rotated page is trimmed on the edge the reader sees', () {
    final out = cropped(
      const PageMargins(top: 50),
      pageOne: '/Type /Page /Parent 2 0 R /Contents 4 0 R /Rotate 90',
    );

    // Displayed clockwise, the reader's top edge is the /MediaBox left edge.
    expect(boxIn(objectBody(out, 3), 'CropBox'), [50, 0, 595, 842]);
  });

  test('rotation is inherited from the pages node', () {
    final out = cropped(
      const PageMargins(top: 50),
      pagesNode:
          '/Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
          '/MediaBox [0 0 595 842] /Rotate 90',
    );

    expect(boxIn(objectBody(out, 3), 'CropBox'), [50, 0, 595, 842]);
  });

  test('a bleed box is clipped inside the crop box', () {
    final out = cropped(
      const PageMargins(left: 100),
      pageOne:
          '/Type /Page /Parent 2 0 R /Contents 4 0 R '
          '/BleedBox [0 0 595 842]',
    );

    expect(boxIn(objectBody(out, 3), 'BleedBox'), [100, 0, 595, 842]);
  });

  test('a page too narrow to trim is left alone, and the rest still crop', () {
    final out = cropped(
      const PageMargins(left: 400, right: 400),
      pageOne:
          '/Type /Page /Parent 2 0 R /Contents 4 0 R '
          '/MediaBox [0 0 200 842]',
      pagesNode:
          '/Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
          '/MediaBox [0 0 2000 842]',
    );

    expect(RegExp(r'(?<![0-9])3 0 obj').allMatches(out).length, 1);
    expect(boxIn(objectBody(out, 5), 'CropBox'), [400, 0, 1600, 842]);
  });

  test('the update ends with a trailer that chains to the old one', () {
    final out = cropped(const PageMargins(left: 10));

    expect(out, contains('/Prev 9'));
    expect(out.trimRight(), endsWith('%%EOF'));
  });

  test('a trim of nothing is refused', () {
    expect(
      () => writeCroppedPages(document(), const PageMargins()),
      throwsArgumentError,
    );
  });

  test('a document where no page can be trimmed is refused', () {
    expect(
      () => writeCroppedPages(document(), const PageMargins(left: 900)),
      throwsA(isA<EmptyDocument>()),
    );
  });
}
