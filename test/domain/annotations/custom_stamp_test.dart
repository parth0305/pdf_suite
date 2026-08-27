import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

Stamp stampOf({String? custom, StampPreset preset = StampPreset.draft}) =>
    Stamp(
      preset: preset,
      pageIndex: 0,
      anchorPt: const PdfPoint(10, 20),
      customLabel: custom,
    );

void main() {
  group('custom wording', () {
    test('a preset stamp keeps its own words', () {
      expect(stampOf().label, 'DRAFT');
    });

    test('a custom label replaces them', () {
      expect(stampOf(custom: 'PAID IN FULL').label, 'PAID IN FULL');
    });

    // A blank field is not a stamp reading "". Falling back to the preset is
    // better than putting an empty box on the page.
    test('a blank custom label falls back to the preset', () {
      expect(stampOf(custom: '').label, 'DRAFT');
      expect(stampOf(custom: '   ').label, 'DRAFT');
    });

    test('surrounding whitespace is trimmed', () {
      expect(stampOf(custom: '  PAID  ').label, 'PAID');
    });

    // The preset still decides the colour, so a custom stamp looks like the
    // others rather than like a stray piece of text.
    test('the colour still comes from the preset', () {
      expect(
        stampOf(custom: 'PAID', preset: StampPreset.approved).colorArgb,
        stampOf(preset: StampPreset.approved).colorArgb,
      );
    });

    // A date stamp is a custom label with the date formatted in - there is no
    // separate mechanism, because there does not need to be one.
    test('a date stamp is just a custom label', () {
      expect(stampOf(custom: '28 Aug 2026').label, '28 Aug 2026');
    });
  });
}
