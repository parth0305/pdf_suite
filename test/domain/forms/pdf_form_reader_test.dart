import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/forms/form_field.dart';
import 'package:folio/domain/forms/pdf_form_reader.dart';

import '../../../scripts/pdf_fixture_builder.dart';

PdfFormReader read() =>
    PdfFormReader.parse(latin1.decode(buildFormPdf(), allowInvalid: true));

FormField field(String name) => read().fields.firstWhere((f) => f.name == name);

void main() {
  test('every field in the form is found', () {
    expect(
      read().fields.map((f) => f.name),
      containsAll([
        'full name',
        'membership number',
        'newsletter',
        'plan',
        'country',
        'issued on',
      ]),
    );
  });

  // A radio group is ONE field with several widgets, not several fields.
  test('a radio group is a single field with a widget per button', () {
    final plan = field('plan');

    expect(plan.kind, FormFieldKind.radio);
    expect(plan.widgets.length, 2);
    expect(plan.options, ['Basic', 'Premium']);
  });

  test('the value of a radio group lives on the group, not a widget', () {
    expect(field('plan').objectNumber, 8);
  });

  test('a checkbox is a checkbox and not a radio', () {
    expect(field('newsletter').kind, FormFieldKind.checkBox);
  });

  // /Yes is a convention, not a rule. Assuming it gives a box that cannot be
  // ticked on half the forms in the world.
  test("a checkbox's on-state is read, not assumed", () {
    expect(field('newsletter').widgets.single.onState, 'On');
  });

  test('a text field is a text field', () {
    expect(field('full name').kind, FormFieldKind.text);
  });

  test('a length limit is read', () {
    expect(field('membership number').maxLength, 8);
  });

  test('a choice field offers what a person would recognise', () {
    final country = field('country');

    expect(country.kind, FormFieldKind.choice);
    expect(country.options, ['India', 'United Kingdom']);
    expect(country.isCombo, isTrue);
  });

  test('a read-only field is found, and marked unfillable', () {
    final issued = field('issued on');

    expect(issued.isReadOnly, isTrue);
    expect(issued.isFillable, isFalse);
    expect(issued.value, '2026-08-28');
  });

  // The widget does not say which page it is on; the page's /Annots does.
  // Assuming page one fills the second page's fields invisibly.
  test('widgets know which page they are drawn on', () {
    expect(field('full name').widgets.single.pageIndex, 0);
    expect(field('signed by').widgets.single.pageIndex, 1);
  });

  test('a signature field is found and left unfillable', () {
    final signature = field('signed by');

    expect(signature.kind, FormFieldKind.signature);
    expect(signature.isFillable, isFalse);
  });

  test('a widget rectangle is read', () {
    final rect = field('full name').widgets.single.rect;

    expect(rect.left, 200);
    expect(rect.right, 500);
    expect(rect.height, 25);
  });

  test("a field's default appearance is read", () {
    expect(field('full name').defaultAppearance, '/Helv 12 Tf 0 g');
  });

  test('a document with no form has no fields', () {
    final plain = latin1.decode(
      buildPdf(generatedPages(1)),
      allowInvalid: true,
    );

    expect(PdfFormReader.parse(plain).hasForm, isFalse);
  });

  // An XFA document's fields live in an XML payload. Filling the AcroForm
  // shell produces a file whose two halves disagree.
  test('an XFA form is refused rather than half-filled', () {
    final xfa = latin1
        .decode(buildFormPdf(), allowInvalid: true)
        .replaceFirst(
          '/AcroForm << /Fields',
          '/AcroForm << /XFA 20 0 R /Fields',
        );

    expect(
      () => PdfFormReader.parse(xfa),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  group('inheritance', () {
    // /FT, /Ff and /V are inheritable. A kid that states none of them is not
    // an untyped text field, it is whatever its parent is.
    test('a kid inherits its type and flags from the parent field', () {
      final source = latin1
          .decode(buildFormPdf(), allowInvalid: true)
          .replaceFirst(
            '<< /FT /Btn /Ff 32768 /T (plan) /Kids [9 0 R 10 0 R] /V /Off >>',
            '<< /FT /Btn /Ff 32768 /T (plan) /Kids [15 0 R] /V /Off >>',
          )
          .replaceFirst(
            'xref',
            '15 0 obj\n<< /T (deluxe) /Kids [9 0 R] >>\nendobj\nxref',
          );

      final deluxe = PdfFormReader.parse(
        source,
      ).fields.firstWhere((f) => f.name == 'plan.deluxe');

      expect(deluxe.kind, FormFieldKind.radio);
    });
  });

  group('field kinds', () {
    test('a pushbutton is not something to fill in', () {
      expect(kindOf('Btn', 65536), FormFieldKind.pushButton);
    });

    test('a radio is a radio', () {
      expect(kindOf('Btn', 32768), FormFieldKind.radio);
    });

    test('a plain button is a checkbox', () {
      expect(kindOf('Btn', 0), FormFieldKind.checkBox);
    });

    test('a signature field is left alone', () {
      expect(kindOf('Sig', 0).name, 'signature');
      expect(
        const FormField(
          name: 's',
          kind: FormFieldKind.signature,
          objectNumber: 1,
          widgets: [],
        ).isFillable,
        isFalse,
      );
    });

    test('multiline is a text flag, not a universal one', () {
      const text = FormField(
        name: 't',
        kind: FormFieldKind.text,
        objectNumber: 1,
        widgets: [],
        flags: 4096,
      );
      const button = FormField(
        name: 'b',
        kind: FormFieldKind.checkBox,
        objectNumber: 1,
        widgets: [],
        flags: 4096,
      );

      expect(text.isMultiline, isTrue);
      expect(button.isMultiline, isFalse);
    });
  });
}
