import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation_session.dart';
import 'package:folio/domain/annotations/annotation.dart';
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
    expect(s.markups, isEmpty);
    expect(s.isEmpty, isTrue);
    expect(s.isDirty, isFalse);
    expect(s.canUndo, isFalse);
  });

  test('markups are unmodifiable from outside', () {
    final s = AnnotationSession();
    expect(() => s.markups.add(markup()), throwsUnsupportedError);
  });

  test('adding makes the session dirty', () {
    final s = AnnotationSession()..add(markup());
    expect(s.markups, hasLength(1));
    expect(s.isDirty, isTrue);
    expect(s.canUndo, isTrue);
  });

  test('removeAt deletes the right one', () {
    final s = AnnotationSession()
      ..add(markup(kind: MarkupKind.highlight))
      ..add(markup(kind: MarkupKind.underline))
      ..removeAt(0);

    expect(s.markups.single.kind, MarkupKind.underline);
  });

  test('an out-of-range removal throws', () {
    final s = AnnotationSession()..add(markup());
    expect(() => s.removeAt(5), throwsRangeError);
  });

  test('undo restores the previous state', () {
    final s = AnnotationSession()..add(markup());
    s.undo();

    expect(s.markups, isEmpty);
    expect(s.isDirty, isFalse);
  });

  test('redo reapplies', () {
    final s = AnnotationSession()..add(markup());
    s.undo();
    s.redo();
    expect(s.markups, hasLength(1));
  });

  test('undo past the beginning is a safe no-op', () {
    final s = AnnotationSession();
    s.undo();
    expect(s.markups, isEmpty);
  });

  test('redo past the end is a safe no-op', () {
    final s = AnnotationSession()..add(markup());
    s.undo();
    s.redo();
    s.redo();
    expect(s.markups, hasLength(1));
  });

  test('a new addition after undo discards the redo branch', () {
    final s = AnnotationSession()..add(markup(kind: MarkupKind.highlight));
    s.undo();
    s.add(markup(kind: MarkupKind.strikeOut));

    expect(s.canRedo, isFalse);
    expect(s.markups.single.kind, MarkupKind.strikeOut);
  });

  test('markupsOnPage filters by page', () {
    final s = AnnotationSession()
      ..add(markup(page: 0))
      ..add(markup(page: 2))
      ..add(markup(page: 0));

    expect(s.markupsOnPage(0), hasLength(2));
    expect(s.markupsOnPage(2), hasLength(1));
    expect(s.markupsOnPage(1), isEmpty);
  });
}
