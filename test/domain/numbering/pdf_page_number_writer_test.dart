import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/numbering/page_numbers.dart';
import 'package:folio/domain/numbering/pdf_page_number_writer.dart';

Uint8List threePages() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
    '/Resources << /Font << /Own 9 0 R >> >> >>\nendobj\n'
    '4 0 obj\n<< /Length 9 >>\nstream\nPAGE-ONE!\nendstream\nendobj\n'
    '5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>\nendobj\n'
    '6 0 obj\n<< /Length 9 >>\nstream\nPAGE-TWO!\nendstream\nendobj\n'
    '7 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 8 0 R >>\nendobj\n'
    '8 0 obj\n<< /Length 11 >>\nstream\nPAGE-THREE!\nendstream\nendobj\n'
    'xref\n0 10\n0000000000 65535 f \n'
    'trailer\n<< /Size 10 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

String numbered([PageNumbering numbering = const PageNumbering()]) => latin1
    .decode(writePageNumbers(threePages(), numbering), allowInvalid: true);

/// The page dictionary as it stands after the update - the LAST definition,
/// which is what a reader walking the trailer chain backwards sees.
/// The negative lookbehind matters: without it `3 0 obj` also matches inside
/// `13 0 obj`, and this update creates object 13. Taking `.last` then returned
/// a content stream instead of the page.
String pageDict(String out, int objectNumber) => RegExp(
  '(?<![0-9])$objectNumber 0 obj(.*?)endobj',
  dotAll: true,
).allMatches(out).last.group(1)!;

/// Whether every `<<` in [dict] has a matching `>>`.
///
/// A malformed dictionary still CONTAINS all the right text, so a `contains`
/// check passes against one - which is how a mutation that mangled the page's
/// own /Font slipped through. The braces are what a reader actually needs.
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
  test('the original bytes are untouched', () {
    final original = threePages();

    expect(
      writePageNumbers(
        original,
        const PageNumbering(),
      ).sublist(0, original.length),
      original,
    );
  });

  test('every page gets a number', () {
    final out = numbered();

    for (final text in ['(1) Tj', '(2) Tj', '(3) Tj']) {
      expect(out, contains(text));
    }
  });

  test('the page keeps its own drawing', () {
    final out = numbered();

    expect(pageDict(out, 3), matches(RegExp(r'/Contents \[4 0 R \d+ 0 R\]')));
    expect(out, contains('PAGE-ONE!'));
  });

  // Replacing /Font would strip the page's own, and its text would lose its
  // typeface.
  test('the page keeps its own font', () {
    final page = pageDict(numbered(), 3);

    expect(page, contains('/Own 9 0 R'));
    expect(page, contains('/PgF1'));
    expect(RegExp(r'/Font').allMatches(page).length, 1);
  });

  // A dictionary that still contains the right text but does not balance is
  // unreadable, and every `contains` assertion above would pass against one.
  test('every rewritten page dictionary is well formed', () {
    final out = numbered();

    for (final objectNumber in [3, 5, 7]) {
      expect(
        bracesBalance(pageDict(out, objectNumber)),
        isTrue,
        reason: 'object $objectNumber: ${pageDict(out, objectNumber)}',
      );
    }
  });

  test('a page with no resources at all gets them', () {
    final page = pageDict(numbered(), 5);

    expect(page, contains('/Resources'));
    expect(page, contains('/PgF1'));
  });

  test('one font object serves the document', () {
    expect(RegExp(r'/BaseFont /Helvetica').allMatches(numbered()).length, 1);
  });

  group('skipping the first page', () {
    const skipping = PageNumbering(skipFirst: true);

    // A skipped page must be left completely alone - not given an empty
    // content stream and a pointless rewrite.
    test('the title page is not rewritten at all', () {
      final out = numbered(skipping);

      expect(
        RegExp(r'(?<![0-9])3 0 obj').allMatches(out).length,
        1,
        reason: 'page 3 appears only in the original bytes',
      );
    });

    test('the page after it is page one', () {
      final out = numbered(skipping);

      expect(out, contains('(1) Tj'));
      expect(out, contains('(2) Tj'));
      expect(out, isNot(contains('(3) Tj')));
    });
  });

  test('the trailer chains to the previous one and keeps /Root', () {
    final out = numbered();
    final trailer = out.substring(out.lastIndexOf('trailer'));

    expect(trailer, contains('/Prev 9'));
    expect(trailer, contains('/Root 1 0 R'));
  });

  test('a document with no pages is refused', () {
    final empty = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        'xref\n0 2\n0000000000 65535 f \n'
        'trailer\n<< /Size 2 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
      ),
    );

    expect(
      () => writePageNumbers(empty, const PageNumbering()),
      throwsA(anything),
    );
  });
}
