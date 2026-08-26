import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';

String docWith(String annots, String objects) =>
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
    '/Annots [$annots] >>\nendobj\n'
    '$objects'
    'trailer\n<< /Size 20 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

const highlight =
    '7 0 obj\n<< /Type /Annot /Subtype /Highlight /Rect [60 700 120 712] '
    '/QuadPoints [60 712 120 712 60 700 120 700] /C [1 1 0] /CA 1 /F 4 >>\n'
    'endobj\n';

const ink =
    '8 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [10 20 50 80] '
    '/InkList [[10 20 30 50 50 80]] /C [0 0 1] /CA 1 /F 4 '
    '/BS << /W 3 >> >>\nendobj\n';

const stamp =
    '9 0 obj\n<< /Type /Annot /Subtype /Stamp /Rect [0 0 10 10] >>\nendobj\n';

void main() {
  group('reading annotations back', () {
    test('finds every annotation referenced by the page', () {
      final found = PdfAnnotationReader.parse(
        docWith('7 0 R 8 0 R', '$highlight$ink'),
      ).onPage(0);

      expect(found.map((a) => a.subtype), ['Highlight', 'Ink']);
      expect(found.map((a) => a.objectNumber), [7, 8]);
    });

    test('reads /Rect into PDF space', () {
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', ink),
      ).onPage(0).single;

      expect(a.rectPt.left, 10);
      expect(a.rectPt.bottom, 20);
      expect(a.rectPt.right, 50);
      expect(a.rectPt.top, 80);
    });

    // /C holds components in 0..1, not bytes.
    test('converts /C to opaque ARGB', () {
      final a = PdfAnnotationReader.parse(
        docWith('7 0 R', highlight),
      ).onPage(0).single;

      expect(a.colorArgb, 0xFFFFFF00);
    });

    test('reads the stroke width from /BS /W', () {
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', ink),
      ).onPage(0).single;

      expect(a.strokeWidth, 3);
    });

    test('a missing /C and /BS read as null, not as a default', () {
      final a = PdfAnnotationReader.parse(
        docWith('9 0 R', stamp),
      ).onPage(0).single;

      expect(a.colorArgb, isNull);
      expect(a.strokeWidth, isNull);
    });
  });

  group('restylability', () {
    test('markup with /QuadPoints is restylable as a TextMarkup', () {
      final a = PdfAnnotationReader.parse(
        docWith('7 0 R', highlight),
      ).onPage(0).single;

      expect(a.restylable, isTrue);
      final markup = a.reconstructed! as TextMarkup;
      expect(markup.kind, MarkupKind.highlight);
      expect(markup.quads, hasLength(1));
      expect(markup.quads.single.left, 60);
      expect(markup.quads.single.top, 712);
    });

    test('ink with /InkList is restylable as a DrawingAnnotation', () {
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', ink),
      ).onPage(0).single;

      final drawing = a.reconstructed! as DrawingAnnotation;
      expect(drawing.kind, DrawingKind.ink);
      expect(drawing.points, hasLength(3));
      expect(drawing.points.first.x, 10);
      expect(drawing.points.first.y, 20);
    });

    test('a square is restylable from its /Rect alone', () {
      const square =
          '8 0 obj\n<< /Type /Annot /Subtype /Square /Rect [10 20 50 80] '
          '/C [0 0 1] >>\nendobj\n';
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', square),
      ).onPage(0).single;

      expect(
        (a.reconstructed! as DrawingAnnotation).kind,
        DrawingKind.rectangle,
      );
    });

    // We must not regenerate an appearance for a subtype we do not model:
    // that risks corrupting how another tool's annotation renders.
    test('an unmodelled subtype is delete-only', () {
      final a = PdfAnnotationReader.parse(
        docWith('9 0 R', stamp),
      ).onPage(0).single;

      expect(a.restylable, isFalse);
      expect(a.reconstructed, isNull);
    });

    test('a subtype we model but whose geometry is missing is delete-only', () {
      const brokenInk =
          '8 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [10 20 50 80] >>\n'
          'endobj\n';
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', brokenInk),
      ).onPage(0).single;

      expect(a.restylable, isFalse);
    });
  });

  group('damaged documents', () {
    // A damaged document is not a reason to refuse the whole page.
    test('a dangling reference is skipped, not thrown on', () {
      final found = PdfAnnotationReader.parse(
        docWith('7 0 R 42 0 R', highlight),
      ).onPage(0);

      expect(found, hasLength(1));
      expect(found.single.objectNumber, 7);
    });

    test('all spans pages, including past an empty one', () {
      const twoPages =
          '%PDF-1.4\n'
          '2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>\nendobj\n'
          '3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] >>\nendobj\n'
          '4 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] '
          '/Annots [8 0 R] >>\nendobj\n'
          '$ink'
          'trailer\n<< /Size 20 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      final reader = PdfAnnotationReader.parse(twoPages);
      expect(reader.onPage(0), isEmpty);
      expect(reader.all.map((a) => a.objectNumber), [8]);
    });

    test('a page with no /Annots yields nothing', () {
      const plain =
          '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] >>\nendobj\n'
          'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      expect(PdfAnnotationReader.parse(plain).onPage(0), isEmpty);
    });
  });
}
