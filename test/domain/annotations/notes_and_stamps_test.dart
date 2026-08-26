import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/stamp_appearance.dart';

const note = StickyNote(
  pageIndex: 0,
  anchorPt: PdfPoint(100, 700),
  contents: 'Check this clause',
);

const approved = Stamp(
  preset: StampPreset.approved,
  pageIndex: 0,
  anchorPt: PdfPoint(100, 700),
);

const confidential = Stamp(
  preset: StampPreset.confidential,
  pageIndex: 0,
  anchorPt: PdfPoint(100, 700),
);

void main() {
  group('sticky notes', () {
    test('is a Text annotation', () {
      expect(note.pdfSubtype, 'Text');
    });

    test('is an Annotation', () {
      expect(note, isA<Annotation>());
    });

    test('carries its contents', () {
      expect(note.contents, 'Check this clause');
    });

    test('has a fixed icon size', () {
      expect(StickyNote.iconSizePt, 20);
    });
  });

  group('stamps', () {
    test('is a Stamp annotation', () {
      expect(approved.pdfSubtype, 'Stamp');
    });

    test('every preset has a label and a colour', () {
      for (final preset in StampPreset.values) {
        final s = Stamp(
          preset: preset,
          pageIndex: 0,
          anchorPt: const PdfPoint(0, 0),
        );
        expect(s.label, isNotEmpty);
        expect(s.colorArgb, isNot(0));
      }
    });

    // Sized from the label rather than measured: a fixed width clips the long
    // ones and wastes space on the short ones.
    test('a longer label gives a wider box', () {
      expect(confidential.widthPt, greaterThan(approved.widthPt));
    });

    test('height does not depend on the label', () {
      expect(confidential.heightPt, approved.heightPt);
    });
  });

  group('stamp appearance', () {
    test('draws the label as text', () {
      final s = stampAppearanceStream(approved);

      expect(s, contains('BT'));
      expect(s, contains('ET'));
      expect(s, contains('(APPROVED) Tj'));
    });

    test('names the font resource it will be given', () {
      expect(stampAppearanceStream(approved), contains('/F1'));
    });

    test('draws a box around the label', () {
      expect(stampAppearanceStream(approved), contains('re'));
    });

    test('the dictionary references the font object', () {
      final d = stampAppearanceDict(approved, 42, 9);

      expect(d, contains('/Type /XObject'));
      expect(d, contains('/Subtype /Form'));
      expect(d, contains('/Length 42'));
      expect(d, contains('/Font << /F1 9 0 R >>'));
    });

    test('the BBox matches the stamp box', () {
      final d = stampAppearanceDict(approved, 42, 9);
      expect(
        d,
        contains(
          '/BBox [0 0 ${approved.widthPt.round()} '
          '${approved.heightPt.round()}]',
        ),
      );
    });

    // Standard-14: referenced, never embedded. Embedding a font would be a new
    // dependency on font data we do not have a licence to redistribute.
    test('the font object is a non-embedded standard-14 Helvetica', () {
      final f = helveticaFontObject();

      expect(f, contains('/BaseFont /Helvetica'));
      expect(f, contains('/Subtype /Type1'));
      expect(f, isNot(contains('/FontFile')));
    });
  });
}
