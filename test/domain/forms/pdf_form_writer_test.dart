import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/forms/form_field.dart';
import 'package:folio/domain/forms/pdf_form_reader.dart';
import 'package:folio/domain/forms/pdf_form_writer.dart';

import '../../../scripts/pdf_fixture_builder.dart';

String fill(Map<String, String?> values) => latin1.decode(
  writeFilledForm(Uint8List.fromList(buildFormPdf()), values),
  allowInvalid: true,
);

/// Every form XObject's content, inflated where it was compressed.
///
/// A raw byte search finds nothing in a deflated stream regardless of what is
/// in it, so a search that does not inflate first proves only that the search
/// ran. And this document ships an appearance of its own, so taking the FIRST
/// stream finds the fixture's rather than the one under test.
String appearanceStreams(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final buffer = StringBuffer();

  for (final match in RegExp(
    r'/Subtype /Form(.*?)stream\r?\n',
    dotAll: true,
  ).allMatches(text)) {
    final start = match.end;
    final end = text.indexOf('endstream', start);
    if (end == -1) continue;

    final raw = bytes.sublist(start, end).toList();
    while (raw.isNotEmpty && (raw.last == 0x0a || raw.last == 0x0d)) {
      raw.removeLast();
    }

    buffer.write(
      match.group(1)!.contains('/FlateDecode')
          ? latin1.decode(ZLibCodec().decode(raw), allowInvalid: true)
          : latin1.decode(raw, allowInvalid: true),
    );
  }

  return buffer.toString();
}

String objectBody(String out, int number) => RegExp(
  '(?<![0-9])$number 0 obj(.*?)endobj',
  dotAll: true,
).allMatches(out).last.group(1)!;

/// The form as a reader would see it after the update.
FormField reread(String out, String name) =>
    PdfFormReader.parse(out).fields.firstWhere((f) => f.name == name);

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
  test('a text field takes its value', () {
    final out = fill({'full name': 'Priya Menon'});

    expect(reread(out, 'full name').value, 'Priya Menon');
  });

  // The value has to be VISIBLE, not merely recorded. A /V with no appearance
  // shows as an empty box in any reader that does not regenerate one.
  test('a filled text field is given an appearance to draw', () {
    final bytes = writeFilledForm(Uint8List.fromList(buildFormPdf()), {
      'full name': 'Priya Menon',
    });
    final field = objectBody(latin1.decode(bytes, allowInvalid: true), 5);

    expect(field, contains('/AP'));
    expect(bracesBalance(field), isTrue);

    final stream = appearanceStreams(bytes);
    expect(stream, contains('(Priya Menon) Tj'));
    expect(stream, contains('/Tx BMC'));
  });

  // The premise for every assertion above: a compressed stream contains none
  // of the text being searched for, so a search that finds something proves
  // the inflation works.
  test('the appearance search can see inside a compressed stream', () {
    final bytes = writeFilledForm(Uint8List.fromList(buildFormPdf()), {
      'full name':
          'A value long enough that deflating it actually helps, '
          'repeated repeated repeated repeated repeated repeated',
    });

    expect(latin1.decode(bytes, allowInvalid: true), contains('/FlateDecode'));
    expect(appearanceStreams(bytes), contains('repeated repeated'));
  });

  test('the appearance box is the size of the field', () {
    final out = fill({'full name': 'Priya Menon'});

    // /Rect [200 700 500 725] is 300 by 25.
    expect(out, contains('/BBox [0 0 300 25]'));
  });

  test('the appearance carries the font it names', () {
    final out = fill({'full name': 'Priya Menon'});
    expect(out, contains('/Font << /Helv'));
  });

  test('a checkbox is ticked by its own state name', () {
    final out = fill({'newsletter': 'On'});
    final widget = objectBody(out, 7);

    expect(widget, contains('/AS /On'));
    expect(reread(out, 'newsletter').value, 'On');
  });

  // /Off is the one state name the specification does fix. A cleared box
  // whose value is some other name claims a state it does not have.
  test('clearing a checkbox sets it to Off', () {
    final out = fill({'newsletter': null});

    expect(objectBody(out, 7), contains('/AS /Off'));
    expect(objectBody(out, 7), contains('/V /Off'));
  });

  // The group holds the value; each widget shows whether it is the chosen one.
  test('a radio group sets the group and every widget', () {
    final out = fill({'plan': 'Premium'});

    expect(objectBody(out, 8), contains('/V /Premium'));
    expect(objectBody(out, 10), contains('/AS /Premium'));
    expect(objectBody(out, 9), contains('/AS /Off'));
  });

  test('a choice field stores the export value', () {
    final out = fill({'country': 'IN'});

    expect(reread(out, 'country').value, 'IN');
  });

  // The person picked "India"; the form's owner reads "IN". Drawing the
  // export value puts a country code in a box that should show a country.
  test('a choice field draws the label, not the export value', () {
    final streams = appearanceStreams(
      writeFilledForm(Uint8List.fromList(buildFormPdf()), {'country': 'IN'}),
    );

    expect(streams, contains('(India) Tj'));
    expect(streams, isNot(contains('(IN) Tj')));
  });

  test('a read-only field is not filled', () {
    final out = fill({'issued on': 'tampered', 'full name': 'Priya'});

    expect(reread(out, 'issued on').value, '2026-08-28');
  });

  test('a signature field is not filled', () {
    expect(() => fill({'signed by': 'Priya'}), throwsA(isA<NoFormFields>()));
  });

  test('an unknown field name changes nothing', () {
    expect(() => fill({'not a field': 'x'}), throwsA(isA<NoFormFields>()));
  });

  test('fields left out keep the values they had', () {
    final out = fill({'full name': 'Priya'});

    expect(reread(out, 'issued on').value, '2026-08-28');
  });

  test('the original bytes are untouched below the update', () {
    final out = fill({'full name': 'Priya'});

    expect(out.indexOf('%PDF-1.4'), 0);
    expect(out, contains('Membership form'));
  });

  test('a document with no form is refused', () {
    expect(
      () => writeFilledForm(Uint8List.fromList(buildPdf(generatedPages(1))), {
        'anything': 'x',
      }),
      throwsA(isA<NoFormFields>()),
    );
  });

  // Field and widget are the same object for a text field. Two emissions of
  // it would leave the first superseded and half the edits lost.
  test('one object carries both its value and its appearance', () {
    final out = fill({'full name': 'Priya'});

    expect(RegExp(r'(?<![0-9])5 0 obj').allMatches(out).length, 2);

    final field = objectBody(out, 5);
    expect(field, contains('/V (Priya)'));
    expect(field, contains('/AP'));
  });

  test('filling twice replaces the value rather than appending one', () {
    final once = writeFilledForm(Uint8List.fromList(buildFormPdf()), {
      'full name': 'Priya',
    });
    final twice = latin1.decode(
      writeFilledForm(once, {'full name': 'Ravi'}),
      allowInvalid: true,
    );

    expect(reread(twice, 'full name').value, 'Ravi');
    expect(bracesBalance(objectBody(twice, 5)), isTrue);
    // A dictionary with two /V entries is corrupt, not merely stale - and a
    // reader that happens to take the first one hides that.
    expect(
      RegExp(r'/V(?![A-Za-z])').allMatches(objectBody(twice, 5)).length,
      1,
    );
  });

  test('a value with brackets in it does not break the dictionary', () {
    final out = fill({'full name': 'Menon (Ms)'});

    expect(reread(out, 'full name').value, 'Menon (Ms)');
    expect(bracesBalance(objectBody(out, 5)), isTrue);
  });
}
