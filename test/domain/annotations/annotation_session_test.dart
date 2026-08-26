import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation_session.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

TextMarkup markup({MarkupKind kind = MarkupKind.highlight, int page = 0}) =>
    TextMarkup(
      kind: kind,
      pageIndex: page,
      quads: const [TextRect(left: 60, top: 712, right: 120, bottom: 700)],
    );

void main() {
  test('starts empty and clean', () {
    final s = AnnotationSession();
    expect(s.annotations, isEmpty);
    expect(s.isEmpty, isTrue);
    expect(s.isDirty, isFalse);
    expect(s.canUndo, isFalse);
  });

  test('markups are unmodifiable from outside', () {
    final s = AnnotationSession();
    expect(() => s.annotations.add(markup()), throwsUnsupportedError);
  });

  test('adding makes the session dirty', () {
    final s = AnnotationSession()..add(markup());
    expect(s.annotations, hasLength(1));
    expect(s.isDirty, isTrue);
    expect(s.canUndo, isTrue);
  });

  test('removeAt deletes the right one', () {
    final s = AnnotationSession()
      ..add(markup(kind: MarkupKind.highlight))
      ..add(markup(kind: MarkupKind.underline))
      ..removeAt(0);

    expect((s.annotations.single as TextMarkup).kind, MarkupKind.underline);
  });

  test('an out-of-range removal throws', () {
    final s = AnnotationSession()..add(markup());
    expect(() => s.removeAt(5), throwsRangeError);
  });

  test('undo restores the previous state', () {
    final s = AnnotationSession()..add(markup());
    s.undo();

    expect(s.annotations, isEmpty);
    expect(s.isDirty, isFalse);
  });

  test('redo reapplies', () {
    final s = AnnotationSession()..add(markup());
    s.undo();
    s.redo();
    expect(s.annotations, hasLength(1));
  });

  test('undo past the beginning is a safe no-op', () {
    final s = AnnotationSession();
    s.undo();
    expect(s.annotations, isEmpty);
  });

  test('redo past the end is a safe no-op', () {
    final s = AnnotationSession()..add(markup());
    s.undo();
    s.redo();
    s.redo();
    expect(s.annotations, hasLength(1));
  });

  test('a new addition after undo discards the redo branch', () {
    final s = AnnotationSession()..add(markup(kind: MarkupKind.highlight));
    s.undo();
    s.add(markup(kind: MarkupKind.strikeOut));

    expect(s.canRedo, isFalse);
    expect((s.annotations.single as TextMarkup).kind, MarkupKind.strikeOut);
  });

  test('markupsOnPage filters by page', () {
    final s = AnnotationSession()
      ..add(markup(page: 0))
      ..add(markup(page: 2))
      ..add(markup(page: 0));

    expect(s.annotationsOnPage(0), hasLength(2));
    expect(s.annotationsOnPage(2), hasLength(1));
    expect(s.annotationsOnPage(1), isEmpty);
  });

  group('mixed annotation types', () {
    test('holds markup and drawings together', () {
      final s = AnnotationSession()
        ..add(markup())
        ..add(
          const DrawingAnnotation(
            kind: DrawingKind.ink,
            pageIndex: 0,
            points: [PdfPoint(0, 0), PdfPoint(10, 10)],
          ),
        );

      expect(s.annotations, hasLength(2));
      expect(s.annotations.map((a) => a.pdfSubtype), ['Highlight', 'Ink']);
    });

    // One undo stack across both kinds is the whole reason for generalising.
    test('undo crosses annotation types', () {
      final s = AnnotationSession()
        ..add(markup())
        ..add(
          const DrawingAnnotation(
            kind: DrawingKind.rectangle,
            pageIndex: 0,
            points: [PdfPoint(0, 0), PdfPoint(10, 10)],
          ),
        );

      s.undo();
      expect(s.annotations, hasLength(1));
      expect(s.annotations.single, isA<TextMarkup>());

      s.undo();
      expect(s.annotations, isEmpty);
    });

    test('annotationsOnPage filters both kinds', () {
      final s = AnnotationSession()
        ..add(markup(page: 0))
        ..add(
          const DrawingAnnotation(
            kind: DrawingKind.ink,
            pageIndex: 0,
            points: [PdfPoint(0, 0), PdfPoint(1, 1)],
          ),
        )
        ..add(markup(page: 3));

      expect(s.annotationsOnPage(0), hasLength(2));
      expect(s.annotationsOnPage(3), hasLength(1));
    });
  });
}
