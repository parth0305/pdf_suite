import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation_transform.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

const from = TextRect(left: 0, bottom: 0, right: 100, top: 100);
const shifted = TextRect(left: 200, bottom: 300, right: 300, top: 400);
const doubled = TextRect(left: 0, bottom: 0, right: 200, top: 200);

SavedAnnotation annotationOf(String subtype) => SavedAnnotation(
  objectNumber: 7,
  pageIndex: 0,
  subtype: subtype,
  rectPt: from,
  rawDictionary: '<< >>',
);

void main() {
  group('transformPoint', () {
    test('maps each corner onto the corresponding corner', () {
      expect(
        transformPoint(const PdfPoint(0, 0), from: from, to: shifted).x,
        200,
      );
      expect(
        transformPoint(const PdfPoint(0, 0), from: from, to: shifted).y,
        300,
      );
      expect(
        transformPoint(const PdfPoint(100, 100), from: from, to: shifted).x,
        300,
      );
      expect(
        transformPoint(const PdfPoint(100, 100), from: from, to: shifted).y,
        400,
      );
    });

    test('scales interior points', () {
      final p = transformPoint(const PdfPoint(50, 50), from: from, to: doubled);
      expect(p.x, 100);
      expect(p.y, 100);
    });

    // A zero-width rect would divide by zero and produce NaN coordinates,
    // which render nowhere at all.
    test('a zero-area source does not divide by zero', () {
      const flat = TextRect(left: 10, bottom: 10, right: 10, top: 10);
      final p = transformPoint(const PdfPoint(10, 10), from: flat, to: shifted);

      expect(p.x.isFinite, isTrue);
      expect(p.y.isFinite, isTrue);
    });
  });

  group('transformAnnotationDict', () {
    const inkDict =
        '<< /Type /Annot /Subtype /Ink /Rect [0 0 100 100] '
        '/InkList [[0 0 50 50] [100 100 0 100]] /C [1 0 0] /CA 1 /F 4 '
        '/BS << /W 3 >> /AP << /N 9 0 R >> >>';

    test('rewrites /Rect', () {
      final out = transformAnnotationDict(inkDict, from: from, to: shifted);
      expect(out, contains('/Rect [200 300 300 400]'));
    });

    // Rewriting /Rect alone leaves geometry pointing at the old position, so a
    // later restyle regenerates the appearance back where it started.
    test('rewrites /InkList by the same affine', () {
      final out = transformAnnotationDict(inkDict, from: from, to: shifted);
      expect(out, contains('/InkList [[200 300 250 350] [300 400 200 400]]'));
    });

    test('rewrites /L for a line', () {
      const lineDict =
          '<< /Type /Annot /Subtype /Line /Rect [0 0 100 100] '
          '/L [0 0 100 100] >>';
      final out = transformAnnotationDict(lineDict, from: from, to: shifted);

      expect(out, contains('/L [200 300 300 400]'));
    });

    test('rewrites /QuadPoints', () {
      const markupDict =
          '<< /Type /Annot /Subtype /Highlight /Rect [0 0 100 100] '
          '/QuadPoints [0 100 100 100 0 0 100 0] >>';
      final out = transformAnnotationDict(markupDict, from: from, to: shifted);

      expect(out, contains('/QuadPoints [200 400 300 400 200 300 300 300]'));
    });

    // A note or a stamp has no geometry key; /Rect is the whole story.
    test('a dictionary with no geometry key changes only its /Rect', () {
      const noteDict =
          '<< /Type /Annot /Subtype /Text /Rect [0 0 100 100] '
          '/Contents (Hello) /Name /Note >>';
      final out = transformAnnotationDict(noteDict, from: from, to: shifted);

      expect(out, contains('/Rect [200 300 300 400]'));
      expect(out, contains('/Contents (Hello)'));
    });

    test('colour, width and the appearance reference all survive', () {
      final out = transformAnnotationDict(inkDict, from: from, to: shifted);

      expect(out, contains('/C [1 0 0]'));
      expect(out, contains('/BS << /W 3 >>'));
      expect(out, contains('/AP << /N 9 0 R >>'));
    });

    test('a zero-area source returns the dictionary unchanged', () {
      const flat = TextRect(left: 10, bottom: 10, right: 10, top: 10);
      expect(
        transformAnnotationDict(inkDict, from: flat, to: shifted),
        inkDict,
      );
    });
  });

  group('lockAspect', () {
    const original = TextRect(left: 0, bottom: 0, right: 200, top: 100);

    test('preserves the ratio when the drag is too tall', () {
      final locked = lockAspect(
        const TextRect(left: 0, bottom: 0, right: 200, top: 400),
        original: original,
      );

      expect(
        (locked.right - locked.left) / (locked.top - locked.bottom),
        closeTo(2, 0.001),
      );
    });

    test('preserves the ratio when the drag is too wide', () {
      final locked = lockAspect(
        const TextRect(left: 0, bottom: 0, right: 800, top: 100),
        original: original,
      );

      expect(
        (locked.right - locked.left) / (locked.top - locked.bottom),
        closeTo(2, 0.001),
      );
    });

    test('keeps the top-left corner anchored', () {
      final locked = lockAspect(
        const TextRect(left: 50, bottom: 0, right: 250, top: 400),
        original: original,
      );

      expect(locked.left, 50);
      expect(locked.top, 400);
    });
  });

  group('what may be moved', () {
    test('markup is anchored to its words', () {
      for (final subtype in ['Highlight', 'Underline', 'StrikeOut']) {
        expect(annotationOf(subtype).movable, isFalse, reason: subtype);
        expect(annotationOf(subtype).resizable, isFalse, reason: subtype);
      }
    });

    test('drawings, notes and stamps move', () {
      for (final subtype in [
        'Ink',
        'Square',
        'Circle',
        'Line',
        'Text',
        'Stamp',
      ]) {
        expect(annotationOf(subtype).movable, isTrue, reason: subtype);
      }
    });

    // Every viewer draws a /Text icon at a fixed size, so there is nothing for
    // a resize to change.
    test('a note moves but does not resize', () {
      expect(annotationOf('Text').movable, isTrue);
      expect(annotationOf('Text').resizable, isFalse);
    });

    test('a stamp resizes even though it cannot be restyled', () {
      final stamp = annotationOf('Stamp');

      expect(stamp.restylable, isFalse);
      expect(stamp.resizable, isTrue);
    });
  });
}
