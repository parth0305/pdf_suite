import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/forms/field_appearance.dart';
import 'package:folio/domain/forms/form_field.dart';

const box = TextRect(left: 0, bottom: 0, right: 200, top: 24);

void main() {
  group('DefaultAppearance', () {
    test('reads the font and size a field asks for', () {
      final da = DefaultAppearance.parse('/Helv 12 Tf 0 g');

      expect(da.fontName, 'Helv');
      expect(da.size, 12);
    });

    // Zero means "fit it to the box", not "draw at nothing".
    test('an auto size is resolved against the box', () {
      final da = DefaultAppearance.parse('/Helv 0 Tf 0 g');

      expect(da.size, 0);
      expect(da.sizeFor(24), 12);
      expect(da.sizeFor(12), 8);
    });

    test('an auto size never resolves to zero in the stream', () {
      expect(
        DefaultAppearance.parse('/Helv 0 Tf 0 g').resolvedFor(24),
        contains('12 Tf'),
      );
    });

    test('a stated size is left exactly as the form wrote it', () {
      const da = '/Helv 9 Tf 0.2 0.2 0.6 rg';

      expect(DefaultAppearance.parse(da).resolvedFor(24), da);
    });

    test('a field with no /DA still gets a font', () {
      expect(DefaultAppearance.parse(null).fontName, fieldFontName);
    });
  });

  group('fieldAppearanceStream', () {
    test('marks itself as form content and clips to the box', () {
      final stream = fieldAppearanceStream(
        value: 'Priya',
        rect: box,
        appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
      );

      expect(stream, contains('/Tx BMC'));
      expect(stream, contains('EMC'));
      // Without the clip, a value longer than its field runs across the page.
      expect(stream, contains('0 0 200 24 re W n'));
    });

    test('draws the value', () {
      expect(
        fieldAppearanceStream(
          value: 'Priya',
          rect: box,
          appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
        ),
        contains('(Priya) Tj'),
      );
    });

    test('a bracket in the value is escaped', () {
      expect(
        fieldAppearanceStream(
          value: 'Menon (Ms)',
          rect: box,
          appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
        ),
        contains(r'(Menon \(Ms\)) Tj'),
      );
    });

    // A single-line field's text sits level with its label; a newline in it
    // would otherwise draw a second line outside the box.
    test('a single-line field draws one line whatever it is given', () {
      final stream = fieldAppearanceStream(
        value: 'one\ntwo',
        rect: box,
        appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
      );

      expect('Tj'.allMatches(stream).length, 1);
      expect(stream, contains('(one two) Tj'));
    });

    test('a multiline field draws a line each', () {
      final stream = fieldAppearanceStream(
        value: 'one\ntwo',
        rect: const TextRect(left: 0, bottom: 0, right: 200, top: 60),
        appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
        multiline: true,
      );

      expect('Tj'.allMatches(stream).length, 2);
    });

    test('lines go down the box, not up it', () {
      final stream = fieldAppearanceStream(
        value: 'one\ntwo',
        rect: const TextRect(left: 0, bottom: 0, right: 200, top: 60),
        appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
        multiline: true,
      );

      final ys = RegExp(
        r'1 0 0 1 [\d.]+ ([\d.-]+) Tm',
      ).allMatches(stream).map((m) => double.parse(m.group(1)!)).toList();

      expect(ys.length, 2);
      expect(ys[1], lessThan(ys[0]));
    });

    test('a right-aligned value is pushed towards the right edge', () {
      final left = fieldAppearanceStream(
        value: 'Priya',
        rect: box,
        appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
      );
      final right = fieldAppearanceStream(
        value: 'Priya',
        rect: box,
        appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
        quadding: 2,
      );

      double x(String s) =>
          double.parse(RegExp(r'1 0 0 1 ([\d.]+) ').firstMatch(s)!.group(1)!);

      expect(x(right), greaterThan(x(left)));
    });

    test('a centred value sits between the two', () {
      double x(int q) => double.parse(
        RegExp(r'1 0 0 1 ([\d.]+) ')
            .firstMatch(
              fieldAppearanceStream(
                value: 'Priya',
                rect: box,
                appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
                quadding: q,
              ),
            )!
            .group(1)!,
      );

      expect(x(1), greaterThan(x(0)));
      expect(x(1), lessThan(x(2)));
    });

    // An alignment that pushes text off its own left edge is worse than no
    // alignment at all.
    test('a long value never starts left of the padding', () {
      for (final quadding in [1, 2]) {
        final stream = fieldAppearanceStream(
          value: 'a value far too long for this narrow field to hold',
          rect: box,
          appearance: DefaultAppearance.parse('/Helv 12 Tf 0 g'),
          quadding: quadding,
        );

        expect(
          double.parse(
            RegExp(r'1 0 0 1 (-?[\d.]+) ').firstMatch(stream)!.group(1)!,
          ),
          greaterThanOrEqualTo(2),
          reason: 'quadding $quadding',
        );
      }
    });
  });

  group('displayedValue', () {
    const country = FormField(
      name: 'country',
      kind: FormFieldKind.choice,
      objectNumber: 1,
      widgets: [],
      options: ['India', 'United Kingdom'],
      exports: ['IN', 'GB'],
    );

    test('a choice shows the label for the value stored', () {
      expect(displayedValue(country, 'GB'), 'United Kingdom');
    });

    test('a value that is not an export is shown as it is', () {
      expect(displayedValue(country, 'Nepal'), 'Nepal');
    });

    test('a text field shows what it holds', () {
      expect(
        displayedValue(
          const FormField(
            name: 'n',
            kind: FormFieldKind.text,
            objectNumber: 1,
            widgets: [],
          ),
          'Priya',
        ),
        'Priya',
      );
    });
  });
}
