import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation_edit_session.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';

SavedAnnotation saved(int number, {int page = 0}) => SavedAnnotation(
  objectNumber: number,
  pageIndex: page,
  subtype: 'Square',
  rectPt: const TextRect(left: 0, bottom: 0, right: 10, top: 10),
  rawDictionary: '<< /Subtype /Square >>',
);

const red = AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 4);
const blue = AnnotationStyle(colorArgb: 0xFF0000FF, strokeWidth: 2);

void main() {
  test('starts clean', () {
    final s = AnnotationEditSession([saved(7)]);

    expect(s.isDirty, isFalse);
    expect(s.canUndo, isFalse);
    expect(s.deleted, isEmpty);
    expect(s.restyled, isEmpty);
  });

  test('deleting stages an object number', () {
    final s = AnnotationEditSession([saved(7), saved(8)])..delete(7);

    expect(s.deleted, {7});
    expect(s.isDirty, isTrue);
  });

  // A deleted annotation must disappear from the list immediately, or the
  // user cannot tell the delete registered.
  test('a deleted annotation leaves the visible list', () {
    final s = AnnotationEditSession([saved(7), saved(8)])..delete(7);

    expect(s.annotations.map((a) => a.objectNumber), [8]);
  });

  test('restyling stages a style', () {
    final s = AnnotationEditSession([saved(7)])..restyle(7, red);

    expect(s.restyled[7], red);
    expect(s.styleOf(7), red);
  });

  test('restyling twice keeps only the latest style', () {
    final s = AnnotationEditSession([saved(7)])
      ..restyle(7, red)
      ..restyle(7, blue);

    expect(s.restyled[7], blue);
    expect(s.restyled, hasLength(1));
  });

  // Restyling something then deleting it must not leave a restyle staged for
  // an object that will no longer be referenced.
  test('deleting a restyled annotation drops its staged style', () {
    final s = AnnotationEditSession([saved(7)])
      ..restyle(7, red)
      ..delete(7);

    expect(s.restyled, isEmpty);
    expect(s.deleted, {7});
  });

  test('onPage filters by page', () {
    final s = AnnotationEditSession([saved(7), saved(8, page: 2)]);

    expect(s.onPage(0).map((a) => a.objectNumber), [7]);
    expect(s.onPage(2).map((a) => a.objectNumber), [8]);
  });

  test('undo reverses a delete', () {
    final s = AnnotationEditSession([saved(7)])..delete(7);
    s.undo();

    expect(s.deleted, isEmpty);
    expect(s.annotations, hasLength(1));
    expect(s.isDirty, isFalse);
  });

  test('undo reverses a restyle', () {
    final s = AnnotationEditSession([saved(7)])..restyle(7, red);
    s.undo();

    expect(s.restyled, isEmpty);
  });

  test('undo crosses operation types in order', () {
    final s = AnnotationEditSession([saved(7), saved(8)])
      ..restyle(7, red)
      ..delete(8);

    s.undo();
    expect(s.deleted, isEmpty);
    expect(s.restyled[7], red);

    s.undo();
    expect(s.restyled, isEmpty);
    expect(s.isDirty, isFalse);
  });

  test('undo on a clean session does nothing', () {
    final s = AnnotationEditSession([saved(7)])..undo();
    expect(s.isDirty, isFalse);
  });

  group('moving', () {
    const target = TextRect(left: 200, bottom: 300, right: 300, top: 400);

    test('staging a move makes the session dirty', () {
      final s = AnnotationEditSession([saved(7)])..moveTo(7, target);

      expect(s.moved[7], target);
      expect(s.isDirty, isTrue, reason: 'Save must not stay disabled');
    });

    test('moving twice keeps only the latest rect', () {
      final s = AnnotationEditSession([saved(7)])
        ..moveTo(7, target)
        ..moveTo(7, const TextRect(left: 0, bottom: 0, right: 10, top: 10));

      expect(s.moved[7]!.right, 10);
      expect(s.moved, hasLength(1));
    });

    // A move staged for something about to be unreferenced is dead weight.
    test('deleting a moved annotation drops its staged move', () {
      final s = AnnotationEditSession([saved(7)])
        ..moveTo(7, target)
        ..delete(7);

      expect(s.moved, isEmpty);
      expect(s.deleted, {7});
    });

    test('undo reverses a move', () {
      final s = AnnotationEditSession([saved(7)])..moveTo(7, target);
      s.undo();

      expect(s.moved, isEmpty);
      expect(s.isDirty, isFalse);
    });

    test('undo crosses moves and restyles in order', () {
      final s = AnnotationEditSession([saved(7)])
        ..restyle(7, red)
        ..moveTo(7, target);

      s.undo();
      expect(s.moved, isEmpty);
      expect(s.restyled[7], red);

      s.undo();
      expect(s.restyled, isEmpty);
      expect(s.isDirty, isFalse);
    });
  });
}
