import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/pdf_text_editor.dart';
import 'package:folio/domain/editing/text_edit.dart';

import '../../../scripts/pdf_fixture_builder.dart';

/// A one-page document whose font declares widths, so an edit can be fitted.
Uint8List document({
  String content = 'BT /F1 12 Tf 72 700 Td (Total 48500) Tj ET',
  String font =
      '/Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding /FirstChar 32 /Widths ['
      // Every glyph 500 wide, from space to the end of ASCII.
      '500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 '
      '500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 '
      '500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 '
      '500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 '
      '500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 500 '
      '500 500 500 500 500 500 500 500 500 500 500 500 500 500 500]',
  String pageExtra = '',
  bool compressed = false,
}) {
  final stream = compressed
      ? null
      : '<< /Length ${content.length} >>\nstream\n${content}endstream';

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>',
    '<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> $pageExtra>>',
    stream ?? '',
    '<< $font >>',
  ];

  final assembled = assemble(
    objects,
    '<< /Size ${objects.length + 1} /Root 1 0 R >>',
  );

  return Uint8List.fromList(assembled);
}

/// The same document with its text split across two content streams, and a
/// font that declares widths so an edit in either can be fitted.
Uint8List twoStreams() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>',
    '<< /Type /Page /Parent 2 0 R /Contents [4 0 R 6 0 R] '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length 34 >>\nstream\nBT /F1 12 Tf (First) Tj ET\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding /FirstChar 32 /Widths '
        '[${List.filled(95, '500').join(' ')}] >>',
    '<< /Length 35 >>\nstream\nBT /F1 12 Tf (Second) Tj ET\nendstream',
  ];

  return Uint8List.fromList(assemble(objects, '<< /Size 7 /Root 1 0 R >>'));
}

PdfTextEditor editorOf(Uint8List pdf) => PdfTextEditor.parse(pdf);

void main() {
  group('reading a page', () {
    test('the text on the page is found and read', () {
      final runs = editorOf(document()).runsOn(0);

      expect(runs.single.text, 'Total 48500');
      expect(runs.single.isEditable, isTrue);
    });

    test('a run knows where it is', () {
      final run = editorOf(document()).runsOn(0).single;

      expect(run.x, 72);
      expect(run.y, 700);
    });

    test('a page that does not exist has no runs', () {
      expect(editorOf(document()).runsOn(4), isEmpty);
    });

    // /Contents may be an array, and a page whose text is split across
    // several streams is common enough that reading only the first loses
    // most of it.
    test('text in every content stream is found', () {
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>',
        '<< /Type /Page /Parent 2 0 R /Contents [4 0 R 6 0 R] '
            '/Resources << /Font << /F1 5 0 R >> >> >>',
        '<< /Length 34 >>\nstream\nBT /F1 12 Tf (First) Tj ET\nendstream',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding /WinAnsiEncoding >>',
        '<< /Length 35 >>\nstream\nBT /F1 12 Tf (Second) Tj ET\nendstream',
      ];

      final runs = editorOf(
        Uint8List.fromList(assemble(objects, '<< /Size 7 /Root 1 0 R >>')),
      ).runsOn(0);

      expect(runs.map((r) => r.text), ['First', 'Second']);
    });

    test('runs from different streams say which one they came from', () {
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>',
        '<< /Type /Page /Parent 2 0 R /Contents [4 0 R 6 0 R] '
            '/Resources << /Font << /F1 5 0 R >> >> >>',
        '<< /Length 34 >>\nstream\nBT /F1 12 Tf (First) Tj ET\nendstream',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        '<< /Length 35 >>\nstream\nBT /F1 12 Tf (Second) Tj ET\nendstream',
      ];

      final runs = editorOf(
        Uint8List.fromList(assemble(objects, '<< /Size 7 /Root 1 0 R >>')),
      ).runsOn(0);

      expect(runs.first.contentObject, 4);
      expect(runs.last.contentObject, 6);
    });

    // The document Folio itself produces, read end to end.
    test('the sample document reads', () {
      final runs = editorOf(
        Uint8List.fromList(buildPdf(kSampleThreePage)),
      ).runsOn(0);

      expect(runs.map((r) => r.text), contains('Confidential Invoice'));
    });

    // /Resources is inheritable. A reader that looks only at the page finds
    // no fonts at all on documents that declare them on the pages node - and
    // then every run on every page is uneditable for no stated reason.
    test('fonts declared on the pages node are found', () {
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] '
            '/Resources << /Font << /F1 5 0 R >> >> >>',
        '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>',
        '<< /Length 34 >>\nstream\nBT /F1 12 Tf (First) Tj ET\nendstream',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding /WinAnsiEncoding >>',
      ];

      final runs = editorOf(
        Uint8List.fromList(assemble(objects, '<< /Size 6 /Root 1 0 R >>')),
      ).runsOn(0);

      expect(runs.single.text, 'First');
    });

    // An encoding may be a dictionary rather than a name, and the base it
    // names inside it is what the bytes mean before the exceptions apply.
    test('a base encoding inside an encoding dictionary is used', () {
      final pdf = document(
        content: 'BT /F1 12 Tf 72 700 Td <92> Tj ET',
        font:
            '/Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding << /BaseEncoding /WinAnsiEncoding >>',
      );

      // 0x92 is a right quote in WinAnsi and a control character in Latin-1.
      expect(editorOf(pdf).runsOn(0).single.text, '’');
    });

    test('the exceptions in an encoding dictionary are applied', () {
      final pdf = document(
        content: 'BT /F1 12 Tf 72 700 Td (A) Tj ET',
        font:
            '/Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding << /BaseEncoding /WinAnsiEncoding '
            '/Differences [65 /bullet] >>',
      );

      expect(editorOf(pdf).runsOn(0).single.text, '•');
    });

    test('a compressed content stream is read', () {
      final content = 'BT /F1 12 Tf 72 700 Td (Compressed) Tj ET';
      final deflated = ZLibCodec(level: 9).encode(latin1.encode(content));

      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>',
        '<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
            '/Resources << /Font << /F1 5 0 R >> >> >>',
        '<< /Length ${deflated.length} /Filter /FlateDecode >>\nstream\n'
            '${latin1.decode(deflated, allowInvalid: true)}\nendstream',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding /WinAnsiEncoding >>',
      ];

      final runs = editorOf(
        Uint8List.fromList(assemble(objects, '<< /Size 6 /Root 1 0 R >>')),
      ).runsOn(0);

      expect(runs.single.text, 'Compressed');
    });
  });

  group('room on the line', () {
    // What makes the overlap check real: the gap to whatever is drawn next.
    test('a run followed by another knows the gap between them', () {
      final pdf = document(
        content: 'BT /F1 12 Tf 72 700 Td (ab) Tj 100 0 Td (cd) Tj ET',
      );
      final runs = editorOf(pdf).runsOn(0);

      // Two glyphs at 500 thousandths of 12 point is 12 points wide; the next
      // run starts 100 further on.
      expect(runs.first.availableWidth, closeTo(88, 0.01));
    });

    test('the last run on a line has no gap to measure', () {
      expect(editorOf(document()).runsOn(0).single.availableWidth, isNull);
    });

    // A run on the line below is not what constrains this one. The next run
    // is placed further RIGHT as well as lower, so that the check on the line
    // is the only thing that can rule it out - with it directly below, the
    // separate check on the x position rules it out too and either guard
    // alone looks sufficient.
    test('a run on the next line does not count as room', () {
      final pdf = document(
        content: 'BT /F1 12 Tf 72 700 Td (ab) Tj 20 -20 Td (cd) Tj ET',
      );

      expect(editorOf(pdf).runsOn(0).first.availableWidth, isNull);
    });

    // Text is not always drawn left to right across a line: a page may place
    // a column on the right before one on the left. A run drawn later but
    // sitting further left constrains nothing.
    test('a run drawn later but further left does not count as room', () {
      final pdf = document(
        content: 'BT /F1 12 Tf 300 700 Td (ab) Tj -200 0 Td (cd) Tj ET',
      );

      expect(editorOf(pdf).runsOn(0).first.availableWidth, isNull);
    });
  });

  group('planning against a real page', () {
    test('a replacement that fits is allowed', () {
      final editor = editorOf(document());
      final run = editor.runsOn(0).single;

      expect(editor.plan(run, 'Total 52000'), isA<EditPatch>());
    });

    test('a character the font cannot write is refused', () {
      final editor = editorOf(document());
      final run = editor.runsOn(0).single;
      final plan = editor.plan(run, 'Total ₹48500');

      expect((plan as EditRefused).reason, EditRefusal.missingCharacters);
    });

    test('a replacement that would overrun the next run is refused', () {
      final pdf = document(
        content: 'BT /F1 12 Tf 72 700 Td (ab) Tj 20 0 Td (cd) Tj ET',
      );
      final editor = editorOf(pdf);
      final run = editor.runsOn(0).first;

      expect(
        (editor.plan(run, 'abcdefghij') as EditRefused).reason,
        EditRefusal.wouldOverlap,
      );
    });

    test('a font with no widths cannot be fitted', () {
      final pdf = document(
        font:
            '/Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding /WinAnsiEncoding',
      );
      final editor = editorOf(pdf);
      final run = editor.runsOn(0).single;

      expect(
        (editor.plan(run, 'Total 52000') as EditRefused).reason,
        EditRefusal.unknownWidths,
      );
    });
  });

  group('writing the change back', () {
    Uint8List edited([String replacement = 'Total 52000']) {
      final editor = editorOf(document());
      return editor.apply(editor.runsOn(0).single, replacement);
    }

    test('the new text is what the page now says', () {
      final runs = editorOf(edited()).runsOn(0);

      expect(runs.single.text, 'Total 52000');
    });

    // The original bytes are never rewritten: a reader walking the trailer
    // chain sees the edit, and everything before it is exactly as it was.
    test('the original bytes are still there underneath', () {
      final out = edited();
      final original = document();

      expect(out.sublist(0, original.length), original);
    });

    // A reader finds objects THROUGH the cross-reference table. These tests
    // read the file by scanning it, which is not how a reader works - so a
    // wrong offset is invisible to every other assertion here.
    test('the cross-reference entry points at the new object', () {
      final out = edited();
      final text = latin1.decode(out, allowInvalid: true);

      final xrefAt = int.parse(
        RegExp(
          r'startxref\s+(\d+)\s*%%EOF\s*$',
        ).firstMatch(text.trimRight())!.group(1)!,
      );
      final entry = RegExp(
        r'xref\s+(\d+)\s+1\s+(\d{10})',
      ).firstMatch(text.substring(xrefAt))!;

      final object = int.parse(entry.group(1)!);
      final offset = int.parse(entry.group(2)!);

      expect(
        text.substring(offset, offset + '$object 0 obj'.length),
        '$object 0 obj',
      );
    });

    test('the update chains to the trailer before it', () {
      final text = latin1.decode(edited(), allowInvalid: true);

      expect(text, contains('/Prev'));
      expect(text.trimRight(), endsWith('%%EOF'));
    });

    test('a shorter replacement keeps what follows in place', () {
      final editor = editorOf(
        document(
          content: 'BT /F1 12 Tf 72 700 Td (abcd) Tj 100 0 Td (xy) Tj ET',
        ),
      );
      final out = editor.apply(editor.runsOn(0).first, 'ab');

      // The second run has not moved: its position comes from its own Td,
      // and the adjustment absorbs the difference inside the first.
      expect(editorOf(out).runsOn(0).last.x, 172);
    });

    test('an edit only rewrites the stream it was in', () {
      final editor = editorOf(twoStreams());
      final out = editor.apply(editor.runsOn(0).last, 'Third!');
      final after = editorOf(out).runsOn(0);

      expect(after.map((r) => r.text), ['First', 'Third!']);
    });

    test('a refused edit is refused rather than half-applied', () {
      final editor = editorOf(document());
      final run = editor.runsOn(0).single;

      expect(
        () => editor.apply(run, 'Total ₹1'),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });

    test('an edit can be made twice', () {
      final once = edited('Total 52000');
      final editor = editorOf(once);
      final twice = editor.apply(editor.runsOn(0).single, 'Total 60000');

      expect(editorOf(twice).runsOn(0).single.text, 'Total 60000');
    });
  });
}
