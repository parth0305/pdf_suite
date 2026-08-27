import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/watermark/pdf_watermark_remover.dart';
import 'package:folio/domain/watermark/pdf_watermark_writer.dart';
import 'package:folio/domain/watermark/watermark.dart';

Uint8List twoPages() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n'
    '4 0 obj\n<< /Length 15 >>\nstream\nPAGE-ONE-BODY\nendstream\nendobj\n'
    '5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>\nendobj\n'
    '6 0 obj\n<< /Length 15 >>\nstream\nPAGE-TWO-BODY\nendstream\nendobj\n'
    'xref\n0 7\n0000000000 65535 f \n'
    'trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

/// A long mark, so its stream is compressed and the remover has to inflate it
/// to recognise the watermark font.
const wordy = Watermark(
  text: 'CONFIDENTIAL DRAFT - NOT FOR DISTRIBUTION OR REVIEW',
);

void main() {
  group('removing a watermark Folio applied', () {
    test('the mark is gone from the file', () {
      final marked = writeWatermark(twoPages(), wordy);
      final result = removeFolioWatermark(marked);
      final out = latin1.decode(result.bytes, allowInvalid: true);

      expect(out, isNot(contains('/WMF1')));
      expect(out, isNot(contains('/WMGS')));
      expect(out, isNot(contains('/BaseFont /Helvetica')));
    });

    test('both pages are reported', () {
      final result = removeFolioWatermark(writeWatermark(twoPages(), wordy));

      expect(result.removal.pagesAffected, 2);
      expect(result.removal.foundAnything, isTrue);
    });

    // Removing the reference without dropping the object leaves the watermark
    // in the file, which is not removal.
    test('the watermark objects are dropped, not orphaned', () {
      final result = removeFolioWatermark(writeWatermark(twoPages(), wordy));

      expect(result.removal.objectsDropped, greaterThan(2));
    });

    test('the page content survives', () {
      final result = removeFolioWatermark(writeWatermark(twoPages(), wordy));
      final out = latin1.decode(result.bytes, allowInvalid: true);

      expect(out, contains('PAGE-ONE-BODY'));
      expect(out, contains('PAGE-TWO-BODY'));
    });

    test('both pages still exist and still draw something', () {
      final result = removeFolioWatermark(writeWatermark(twoPages(), wordy));
      final out = latin1.decode(result.bytes, allowInvalid: true);

      expect(RegExp(r'/Type /Page\b').allMatches(out).length, 2);
      expect(RegExp(r'/Contents \[4 0 R\]').allMatches(out).length, 1);
      expect(RegExp(r'/Contents \[6 0 R\]').allMatches(out).length, 1);
    });

    test('a short mark, whose stream is not compressed, is also found', () {
      final result = removeFolioWatermark(
        writeWatermark(twoPages(), const Watermark(text: 'DRAFT')),
      );

      expect(result.removal.pagesAffected, 2);
      expect(
        latin1.decode(result.bytes, allowInvalid: true),
        isNot(contains('(DRAFT) Tj')),
      );
    });
  });

  group('refusing what it cannot identify', () {
    // A watermark applied by another tool carries no marker Folio can trust.
    // Guessing which part of a content stream is "the watermark" is the same
    // problem as redaction, and a button that half-removes something while
    // reporting success is worse than no button.
    test('a document with no Folio watermark is refused', () {
      expect(
        () => removeFolioWatermark(twoPages()),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });

    test('the refusal says why', () {
      expect(
        () => removeFolioWatermark(twoPages()),
        throwsA(
          isA<UnsupportedPdfStructure>().having(
            (e) => e.technicalDetail,
            'technicalDetail',
            contains('Folio'),
          ),
        ),
      );
    });
  });

  test('applying then removing returns the page to its original drawing', () {
    final original = twoPages();
    final result = removeFolioWatermark(writeWatermark(original, wordy));
    final out = latin1.decode(result.bytes, allowInvalid: true);

    // Not byte-identical - the rewrite renumbers the cross-reference table -
    // but the pages draw exactly what they drew before.
    expect(out, contains('PAGE-ONE-BODY'));
    expect(out, isNot(contains('WMF1')));
    expect(out, isNot(contains('Tj')));
  });
}
