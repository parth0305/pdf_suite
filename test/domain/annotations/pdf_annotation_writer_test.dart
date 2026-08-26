import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_annotation_writer.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

Uint8List classicPdf() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\nendobj\n'
    'xref\n0 4\n0000000000 65535 f \n'
    'trailer\n<< /Size 4 /Root 1 0 R >>\n'
    'startxref\n9\n%%EOF\n',
  ),
);

TextMarkup markup([MarkupKind kind = MarkupKind.highlight]) => TextMarkup(
  kind: kind,
  pageIndex: 0,
  quads: const [TextRect(left: 60, top: 712, right: 120, bottom: 700)],
);

void main() {
  test('leaves the original bytes untouched at the front', () {
    final original = classicPdf();
    final out = writeAnnotations(original, [markup()]);

    expect(out.length, greaterThan(original.length));
    expect(out.sublist(0, original.length), original);
  });

  test('emits the annotation with the right subtype and quads', () {
    final text = latin1.decode(writeAnnotations(classicPdf(), [markup()]));

    expect(text, contains('/Subtype /Highlight'));
    expect(text, contains('/QuadPoints'));
    expect(text, contains('60 712 120 712 60 700 120 700'));
  });

  test('emits an appearance stream', () {
    final text = latin1.decode(writeAnnotations(classicPdf(), [markup()]));
    expect(text, contains('/Subtype /Form'));
    expect(text, contains('/AP'));
  });

  test('the page object is overridden with /Annots', () {
    final text = latin1.decode(writeAnnotations(classicPdf(), [markup()]));
    final defs = RegExp(r'3 0 obj(.*?)endobj', dotAll: true).allMatches(text);
    expect(defs.last.group(1), contains('/Annots'));
  });

  test('ends with a trailer chaining to the previous xref', () {
    final text = latin1.decode(writeAnnotations(classicPdf(), [markup()]));
    expect(text, contains('/Prev 9'));
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
  });

  test('writes several markups of different kinds', () {
    final text = latin1.decode(
      writeAnnotations(classicPdf(), [
        markup(),
        markup(MarkupKind.underline),
        markup(MarkupKind.strikeOut),
      ]),
    );

    expect(text, contains('/Subtype /Highlight'));
    expect(text, contains('/Subtype /Underline'));
    expect(text, contains('/Subtype /StrikeOut'));
  });

  test('overrides the page once however many markups it carries', () {
    final text = latin1.decode(
      writeAnnotations(classicPdf(), [markup(), markup(MarkupKind.underline)]),
    );
    // Original definition plus exactly one override.
    expect(RegExp(r'3 0 obj').allMatches(text).length, 2);
  });

  test('an empty markup list returns the document unchanged', () {
    final original = classicPdf();
    expect(writeAnnotations(original, const []), original);
  });

  // Refusing loudly beats producing a file whose annotations never appear.
  test('a cross-reference-stream document is refused', () {
    final xrefStream = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.5\n'
        '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        '4 0 obj\n<< /Type /XRef /Size 5 >>\nstream\n\nendstream\nendobj\n'
        'startxref\n9\n%%EOF\n',
      ),
    );

    expect(
      () => writeAnnotations(xrefStream, [markup()]),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  test('a document with no page object is refused', () {
    final noPages = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        'trailer\n<< /Size 2 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
      ),
    );

    expect(
      () => writeAnnotations(noPages, [markup()]),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  group('drawings', () {
    DrawingAnnotation ink() => const DrawingAnnotation(
      kind: DrawingKind.ink,
      pageIndex: 0,
      strokes: [
        [PdfPoint(60, 700), PdfPoint(90, 730), PdfPoint(120, 700)],
      ],
    );

    test('emits an /Ink annotation with an /InkList', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [ink()]));

      expect(text, contains('/Subtype /Ink'));
      expect(text, contains('/InkList'));
      // Alternating x y, one array per stroke.
      expect(text, contains('[[60 700 90 730 120 700]]'));
    });

    test('emits /Square with a /Rect for a rectangle', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          const DrawingAnnotation(
            kind: DrawingKind.rectangle,
            pageIndex: 0,
            strokes: [
              [PdfPoint(60, 700), PdfPoint(160, 760)],
            ],
          ),
        ]),
      );

      expect(text, contains('/Subtype /Square'));
      expect(text, contains('/Rect [60 700 160 760]'));
    });

    test('emits /Circle for an oval', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          const DrawingAnnotation(
            kind: DrawingKind.ellipse,
            pageIndex: 0,
            strokes: [
              [PdfPoint(60, 700), PdfPoint(160, 760)],
            ],
          ),
        ]),
      );
      expect(text, contains('/Subtype /Circle'));
    });

    test('emits /Line with an /L array', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          const DrawingAnnotation(
            kind: DrawingKind.line,
            pageIndex: 0,
            strokes: [
              [PdfPoint(60, 700), PdfPoint(160, 760)],
            ],
          ),
        ]),
      );

      expect(text, contains('/Subtype /Line'));
      expect(text, contains('/L [60 700 160 760]'));
    });

    test('an arrow declares a line ending so viewers draw the head', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          const DrawingAnnotation(
            kind: DrawingKind.arrow,
            pageIndex: 0,
            strokes: [
              [PdfPoint(60, 700), PdfPoint(160, 760)],
            ],
          ),
        ]),
      );
      expect(text, contains('/LE'));
    });

    test('every drawing gets an appearance stream', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [ink()]));
      expect(text, contains('/AP'));
      expect(text, contains('/Subtype /Form'));
    });

    // The point of the sealed type: one save, both kinds.
    test('markup and drawings write together in one pass', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [markup(), ink()]),
      );

      expect(text, contains('/Subtype /Highlight'));
      expect(text, contains('/Subtype /Ink'));
      // Still exactly one page override.
      expect(RegExp(r'3 0 obj').allMatches(text).length, 2);
    });
  });

  group('notes and stamps', () {
    const note = StickyNote(
      pageIndex: 0,
      anchorPt: PdfPoint(100, 700),
      contents: 'Check this clause',
    );
    const approved = Stamp(
      preset: StampPreset.approved,
      pageIndex: 0,
      anchorPt: PdfPoint(100, 600),
    );

    test('a note is written as /Text with its contents', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [note]));

      expect(text, contains('/Subtype /Text'));
      expect(text, contains('(Check this clause)'));
      expect(text, contains('/Name /Note'));
    });

    test('a note is anchored at an icon-sized /Rect', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [note]));
      expect(text, contains('/Rect [100 680 120 700]'));
    });

    // PDFium draws the icon itself. An /AP we generated could only disagree
    // with what other viewers draw.
    test('a note carries NO appearance stream', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [note]));

      expect(text, isNot(contains('/AP')));
      expect(text, isNot(contains('/Subtype /Form')));
    });

    test('a stamp is written with an appearance stream', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [approved]));

      expect(text, contains('/Subtype /Stamp'));
      expect(text, contains('/AP'));
      expect(text, contains('(APPROVED) Tj'));
    });

    test('a stamp names its preset', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [approved]));
      expect(text, contains('/Name /Approved'));
    });

    // One font object per save, not one per stamp.
    test('several stamps share one font object', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          approved,
          const Stamp(
            preset: StampPreset.draft,
            pageIndex: 0,
            anchorPt: PdfPoint(300, 600),
          ),
        ]),
      );

      expect(RegExp(r'/BaseFont /Helvetica').allMatches(text).length, 1);
    });

    test('a document with no stamps emits no font object', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [note]));
      expect(text, isNot(contains('/BaseFont')));
    });

    // The point of the sealed type: every kind in one pass.
    test('all four annotation kinds write together', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [markup(), note, approved]),
      );

      expect(text, contains('/Subtype /Highlight'));
      expect(text, contains('/Subtype /Text'));
      expect(text, contains('/Subtype /Stamp'));
      // Still exactly one page override.
      expect(RegExp(r'3 0 obj').allMatches(text).length, 2);
    });
  });
}
