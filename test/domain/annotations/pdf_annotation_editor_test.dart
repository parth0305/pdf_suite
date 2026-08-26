import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';

Uint8List annotated() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
    '/Annots [7 0 R 8 0 R] >>\nendobj\n'
    '7 0 obj\n<< /Type /Annot /Subtype /Highlight /Rect [60 700 120 712] '
    '/QuadPoints [60.125 712.5 120 712.5 60.125 700 120 700] /C [1 1 0] '
    '/CA 1 /F 4 /AP << /N 6 0 R >> >>\nendobj\n'
    '8 0 obj\n<< /Type /Annot /Subtype /Square /Rect [10 20 50 80] '
    '/C [0 0 1] /CA 1 /F 4 /BS << /W 3 >> /AP << /N 5 0 R >> >>\nendobj\n'
    'xref\n0 9\n0000000000 65535 f \n'
    'trailer\n<< /Size 9 /Root 1 0 R >>\n'
    'startxref\n9\n%%EOF\n',
  ),
);

void main() {
  group('deleting', () {
    test('drops the reference from an overridden page dictionary', () {
      final text = latin1.decode(
        applyAnnotationEdits(annotated(), deleted: {7}, restyled: const {}),
      );

      final overrides = RegExp(
        r'3 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).toList();
      expect(overrides, hasLength(2), reason: 'original plus one override');
      expect(overrides.last.group(1), contains('8 0 R'));
      expect(overrides.last.group(1), isNot(contains('7 0 R')));
    });

    test('the original bytes are still present, untouched', () {
      final original = annotated();
      final out = applyAnnotationEdits(
        original,
        deleted: {7},
        restyled: const {},
      );

      expect(out.sublist(0, original.length), original);
    });

    test('deleting every annotation leaves an empty /Annots', () {
      final text = latin1.decode(
        applyAnnotationEdits(annotated(), deleted: {7, 8}, restyled: const {}),
      );
      expect(text, contains('/Annots []'));
    });
  });

  group('restyling', () {
    test('overrides the SAME object number', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            8: const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 6),
          },
        ),
      );

      expect(RegExp(r'8 0 obj').allMatches(text).length, 2);
    });

    test('writes the new colour and width', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            8: const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 6),
          },
        ),
      );

      final override = RegExp(
        r'8 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      expect(override, contains('/C [1 0 0]'));
      expect(override, contains('/W 6'));
    });

    // pdfNumber truncates to two decimals, so re-emitting geometry from
    // parsed doubles would move the annotation. It must be copied verbatim.
    test('geometry is copied verbatim, at full precision', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            7: const AnnotationStyle(colorArgb: 0xFF00FF00, strokeWidth: 2),
          },
        ),
      );

      final override = RegExp(
        r'7 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      expect(
        override,
        contains('/QuadPoints [60.125 712.5 120 712.5 60.125 700 120 700]'),
        reason: 'a restyle must not move the annotation by a rounding error',
      );
    });

    test('a fresh appearance stream is emitted and referenced', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            8: const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 6),
          },
        ),
      );

      final override = RegExp(
        r'8 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      expect(override, isNot(contains('/N 5 0 R')));
      expect(override, contains('/AP'));
      expect(text, contains('/Subtype /Form'));
    });

    test('a restyled annotation keeps its place in /Annots', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            8: const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 6),
          },
        ),
      );

      expect(RegExp(r'3 0 obj').allMatches(text).length, 1);
    });
  });

  group('refusals', () {
    test('nothing staged returns the input unchanged', () {
      final original = annotated();
      expect(
        applyAnnotationEdits(original, deleted: const {}, restyled: const {}),
        original,
      );
    });

    test('a cross-reference-stream document is refused', () {
      final modern = Uint8List.fromList(
        latin1.encode(
          '%PDF-1.5\n'
          '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
          '4 0 obj\n<< /Type /XRef /Size 5 >>\nstream\n\nendstream\nendobj\n'
          'startxref\n9\n%%EOF\n',
        ),
      );

      expect(
        () => applyAnnotationEdits(modern, deleted: {7}, restyled: const {}),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });
  });

  group('metadata', () {
    // The newest trailer wins. One that omits /Info discards the document's
    // title and author - the same silent loss SP-2b fixed for page operations.
    test('an existing /Info reference is carried into the new trailer', () {
      final withInfo = Uint8List.fromList(
        latin1.encode(
          latin1
              .decode(annotated())
              .replaceFirst(
                '<< /Size 9 /Root 1 0 R >>',
                '<< /Size 9 /Root 1 0 R /Info 4 0 R >>',
              ),
        ),
      );

      final text = latin1.decode(
        applyAnnotationEdits(withInfo, deleted: {7}, restyled: const {}),
      );

      final trailers = RegExp(
        r'trailer\s*(<<[^>]*(?:>[^>]*)*?>>)',
      ).allMatches(text).toList();
      expect(trailers.last.group(1), contains('/Info 4 0 R'));
    });

    test('a document with no /Info gains none', () {
      final text = latin1.decode(
        applyAnnotationEdits(annotated(), deleted: {7}, restyled: const {}),
      );
      expect(text, isNot(contains('/Info')));
    });
  });
}
