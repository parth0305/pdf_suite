import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/drawing_appearance.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_annotation_writer.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

const twoStrokes = DrawingAnnotation(
  kind: DrawingKind.ink,
  pageIndex: 0,
  strokes: [
    [PdfPoint(10, 10), PdfPoint(20, 20), PdfPoint(30, 10)],
    [PdfPoint(80, 80), PdfPoint(90, 90), PdfPoint(100, 80)],
  ],
);

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

void main() {
  group('geometry', () {
    // Bounding only the first stroke gives a /Rect that is too small and a
    // /BBox that clips most of the signature away.
    test('boundsPt spans every stroke', () {
      final b = twoStrokes.boundsPt;

      expect(b.left, 10);
      expect(b.bottom, 10);
      expect(b.right, 100);
      expect(b.top, 90);
    });

    test('points still reads the first stroke, for shape code', () {
      expect(twoStrokes.points, hasLength(3));
      expect(twoStrokes.points.first.x, 10);
    });

    test('a shape built from two corners still works', () {
      const square = DrawingAnnotation(
        kind: DrawingKind.rectangle,
        pageIndex: 0,
        strokes: [
          [PdfPoint(10, 20), PdfPoint(50, 80)],
        ],
      );

      expect(square.boundsPt.right, 50);
      expect(square.points, hasLength(2));
    });
  });

  group('appearance', () {
    // One moveto per stroke. A single moveto means the strokes are joined by
    // a line through the gap that is not in the document.
    test('emits one subpath per stroke', () {
      final s = drawingAppearanceStream(twoStrokes);

      expect(RegExp(r'\bm\b').allMatches(s).length, 2);
      expect(s, contains('10 10 m'));
      expect(s, contains('80 80 m'));
    });

    test('still strokes the path once', () {
      expect(
        RegExp(
          r'^S$',
          multiLine: true,
        ).allMatches(drawingAppearanceStream(twoStrokes)).length,
        1,
      );
    });
  });

  group('writing', () {
    test('/InkList emits one array per stroke', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [twoStrokes]));

      expect(text, contains('[[10 10 20 20 30 10] [80 80 90 90 100 80]]'));
    });
  });

  group('reading', () {
    // The SP-3c regression: flattening joins strokes when restyled.
    test('a two-stroke /InkList reads back as two strokes', () {
      const doc =
          '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] /Annots [8 0 R] >>\n'
          'endobj\n'
          '8 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [0 0 100 100] '
          '/InkList [[10 10 20 20] [80 80 90 90]] /C [0 0 0] >>\nendobj\n'
          'trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      final ink =
          PdfAnnotationReader.parse(doc).onPage(0).single.reconstructed!
              as DrawingAnnotation;

      expect(ink.strokes, hasLength(2));
      expect(ink.strokes.first, hasLength(2));
      expect(ink.strokes.last.first.x, 80);
    });

    test('a single-stroke /InkList still reads as one stroke', () {
      const doc =
          '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] /Annots [8 0 R] >>\n'
          'endobj\n'
          '8 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [0 0 100 100] '
          '/InkList [[10 10 20 20 30 30]] /C [0 0 0] >>\nendobj\n'
          'trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      final ink =
          PdfAnnotationReader.parse(doc).onPage(0).single.reconstructed!
              as DrawingAnnotation;

      expect(ink.strokes, hasLength(1));
      expect(ink.strokes.single, hasLength(3));
    });
  });
}
