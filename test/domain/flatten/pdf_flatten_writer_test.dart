import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/flatten/pdf_flatten_writer.dart';

/// A page with two annotations: a square with an appearance, and whatever
/// [second] is. Object 9 is the appearance form.
Uint8List document({
  String catalog = '/Type /Catalog /Pages 2 0 R',
  String second =
      '/Type /Annot /Subtype /Text /Rect [0 0 20 20] '
      '/AP << /N 9 0 R >>',
  String pageExtra = '',
}) => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< $catalog >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
    '/Annots [7 0 R 8 0 R] $pageExtra >>\nendobj\n'
    '4 0 obj\n<< /Length 9 >>\nstream\nPAGE-ONE!\nendstream\nendobj\n'
    '7 0 obj\n<< /Type /Annot /Subtype /Square /Rect [100 100 200 200] '
    '/AP << /N 9 0 R >> >>\nendobj\n'
    '8 0 obj\n<< $second >>\nendobj\n'
    '9 0 obj\n<< /Type /XObject /Subtype /Form /BBox [0 0 50 50] '
    '/Length 5 >>\nstream\nDRAWN\nendstream\nendobj\n'
    'xref\n0 10\n0000000000 65535 f \n'
    'trailer\n<< /Size 10 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

String flattened({String? catalog, String? second, String? pageExtra}) =>
    latin1.decode(
      writeFlattened(
        document(
          catalog: catalog ?? '/Type /Catalog /Pages 2 0 R',
          second:
              second ??
              '/Type /Annot /Subtype /Text /Rect [0 0 20 20] '
                  '/AP << /N 9 0 R >>',
          pageExtra: pageExtra ?? '',
        ),
      ),
      allowInvalid: true,
    );

String objectBody(String out, int number) => RegExp(
  '(?<![0-9])$number 0 obj(.*?)endobj',
  dotAll: true,
).allMatches(out).last.group(1)!;

/// Whether every `<<` in [dict] has a matching `>>`. A malformed dictionary
/// still CONTAINS all the right text, which is how a `contains` check passes
/// against one.
bool bracesBalance(String dict) {
  var depth = 0;
  for (var i = 0; i < dict.length - 1; i++) {
    if (dict.startsWith('<<', i)) {
      depth++;
      i++;
    } else if (dict.startsWith('>>', i)) {
      depth--;
      if (depth < 0) return false;
      i++;
    }
  }
  return depth == 0;
}

void main() {
  test('the appearance is painted into the page content', () {
    final out = flattened();
    final content = RegExp(
      r'10 0 obj.*?stream(.*?)endstream',
      dotAll: true,
    ).firstMatch(out)!.group(1)!;

    expect(content, contains('/FlA0 Do'));
    expect(content, contains('/FlA1 Do'));
  });

  test('the appearance form is added to the page resources', () {
    final page = objectBody(flattened(), 3);

    expect(page, contains('/XObject'));
    expect(page, contains('/FlA0 9 0 R'));
    expect(bracesBalance(page), isTrue);
  });

  test('the new content is appended, not substituted for the page', () {
    final page = objectBody(flattened(), 3);

    expect(page, contains('4 0 R'));
    expect(page, contains('/Contents [4 0 R 10 0 R]'));
  });

  test('the flattened annotations are gone from /Annots', () {
    final page = objectBody(flattened(), 3);

    expect(page, isNot(contains('/Annots')));
  });

  test('the original bytes are untouched below the update', () {
    final out = flattened();

    expect(out.indexOf('%PDF-1.4'), 0);
    expect(out, contains('PAGE-ONE!'));
  });

  test('a link is kept in /Annots and not painted', () {
    final out = flattened(
      second:
          '/Type /Annot /Subtype /Link /Rect [0 0 20 20] '
          '/A << /S /URI /URI (https://example.org) >>',
    );
    final page = objectBody(out, 3);
    final content = RegExp(
      r'10 0 obj.*?stream(.*?)endstream',
      dotAll: true,
    ).firstMatch(out)!.group(1)!;

    expect(page, contains('/Annots [8 0 R]'));
    expect('Do'.allMatches(content).length, 1);
  });

  test('a popup is removed without being painted', () {
    final out = flattened(
      second:
          '/Type /Annot /Subtype /Popup /Rect [0 0 20 20] '
          '/AP << /N 9 0 R >>',
    );
    final content = RegExp(
      r'10 0 obj.*?stream(.*?)endstream',
      dotAll: true,
    ).firstMatch(out)!.group(1)!;

    expect(objectBody(out, 3), isNot(contains('/Annots')));
    expect('Do'.allMatches(content).length, 1);
  });

  test('a field with no appearance is left alone', () {
    final out = flattened(
      second:
          '/Type /Annot /Subtype /Widget /FT /Tx /V (Priya) '
          '/Rect [0 0 20 20]',
    );

    expect(objectBody(out, 3), contains('/Annots [8 0 R]'));
  });

  // A viewer that still sees /AcroForm draws its own empty fields straight
  // back over the flattened ones.
  test('a fully flattened form stops being a form', () {
    final out = flattened(
      catalog: '/Type /Catalog /Pages 2 0 R /AcroForm << /Fields [7 0 R] >>',
      second:
          '/Type /Annot /Subtype /Widget /Rect [0 0 20 20] '
          '/AP << /N 9 0 R >>',
    );
    final catalog = objectBody(out, 1);

    expect(catalog, isNot(contains('/AcroForm')));
    expect(catalog, contains('/Pages 2 0 R'));
    expect(bracesBalance(catalog), isTrue);
  });

  test('an /AcroForm reference is removed too', () {
    final out = flattened(
      catalog: '/Type /Catalog /Pages 2 0 R /AcroForm 11 0 R',
      second:
          '/Type /Annot /Subtype /Widget /Rect [0 0 20 20] '
          '/AP << /N 9 0 R >>',
    );

    expect(objectBody(out, 1), isNot(contains('/AcroForm')));
  });

  // A field that could not be flattened still needs its form dictionary.
  test('a form with an unflattened field keeps /AcroForm', () {
    final out = flattened(
      catalog: '/Type /Catalog /Pages 2 0 R /AcroForm << /Fields [8 0 R] >>',
      second:
          '/Type /Annot /Subtype /Widget /FT /Tx /V (Priya) '
          '/Rect [0 0 20 20]',
    );

    expect(objectBody(out, 1), contains('/AcroForm'));
  });

  test('the appearance is placed on the rectangle it occupied', () {
    final out = flattened();
    final content = RegExp(
      r'10 0 obj.*?stream(.*?)endstream',
      dotAll: true,
    ).firstMatch(out)!.group(1)!;

    // /Rect [100 100 200 200] over a [0 0 50 50] box: twice the size, moved
    // to 100,100.
    expect(content, contains('q 2 0 0 2 100 100 cm /FlA0 Do Q'));
  });

  // Two /XObject dictionaries in one /Resources is one too many: a reader
  // takes one of them, and the page's own images are in the other.
  test('an existing /XObject dictionary is merged into, not shadowed', () {
    final page = objectBody(
      flattened(pageExtra: '/Resources << /XObject << /Im0 12 0 R >> >>'),
      3,
    );

    expect('/XObject'.allMatches(page).length, 1);
    expect(page, contains('/Im0 12 0 R'));
    expect(page, contains('/FlA0 9 0 R'));
    expect(bracesBalance(page), isTrue);
  });

  test('a document with nothing to flatten is refused', () {
    final empty = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n'
        'xref\n0 4\n0000000000 65535 f \n'
        'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
      ),
    );

    expect(() => writeFlattened(empty), throwsA(isA<NothingToFlatten>()));
  });

  test('the page keeps resources it already had', () {
    final page = objectBody(
      flattened(pageExtra: '/Resources << /Font << /Own 12 0 R >> >>'),
      3,
    );

    expect(page, contains('/Own 12 0 R'));
    expect(page, contains('/FlA0 9 0 R'));
    expect(bracesBalance(page), isTrue);
  });
}
