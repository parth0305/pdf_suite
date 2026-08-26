import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/features/viewer/annotation_edit_providers.dart';
import 'package:folio/features/viewer/widgets/annotation_selection_overlay.dart';

SavedAnnotation saved(int number) => SavedAnnotation(
  objectNumber: number,
  pageIndex: 0,
  subtype: 'Square',
  rectPt: const TextRect(left: 0, bottom: 0, right: 10, top: 10),
  rawDictionary: '<< /Subtype /Square >>',
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationEditController c() =>
      container.read(annotationEditProvider.notifier);
  AnnotationEditState s() => container.read(annotationEditProvider);

  test('starts with nothing loaded and nothing selected', () {
    expect(s().session.annotations, isEmpty);
    expect(s().selectedObjectNumber, isNull);
  });

  test('loading replaces the session', () {
    c().loadInto([saved(7), saved(8)]);

    expect(s().session.annotations, hasLength(2));
  });

  test('selecting records the object number', () {
    c()
      ..loadInto([saved(7)])
      ..select(7);

    expect(s().selectedObjectNumber, 7);
  });

  test('deleting the selection stages it and clears the selection', () {
    c()
      ..loadInto([saved(7), saved(8)])
      ..select(7)
      ..deleteSelected();

    expect(s().session.deleted, {7});
    expect(
      s().selectedObjectNumber,
      isNull,
      reason: 'a deleted annotation cannot stay selected',
    );
  });

  test('deleting with nothing selected does nothing', () {
    c()
      ..loadInto([saved(7)])
      ..deleteSelected();

    expect(s().session.isDirty, isFalse);
  });

  test('restyling the selection stages a style', () {
    c()
      ..loadInto([saved(7)])
      ..select(7)
      ..restyleSelected(
        const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 5),
      );

    expect(s().session.restyled[7]?.strokeWidth, 5);
  });

  test('undo reverses the last edit', () {
    c()
      ..loadInto([saved(7)])
      ..select(7)
      ..deleteSelected();
    c().undo();

    expect(s().session.deleted, isEmpty);
  });

  test('reset clears everything', () {
    c()
      ..loadInto([saved(7)])
      ..select(7)
      ..deleteSelected();
    c().reset();

    expect(s().session.annotations, isEmpty);
    expect(s().selectedObjectNumber, isNull);
  });

  group('hit testing', () {
    const pageRect = Rect.fromLTWH(0, 0, 595, 842);

    SavedAnnotation box(int number, TextRect rect) => SavedAnnotation(
      objectNumber: number,
      pageIndex: 0,
      subtype: 'Square',
      rectPt: rect,
      rawDictionary: '<< >>',
    );

    test('a tap inside an annotation selects it', () {
      final hit = annotationAtPoint(
        const Offset(30, 792),
        annotations: [
          box(7, const TextRect(left: 10, bottom: 20, right: 50, top: 80)),
        ],
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

      expect(hit, 7);
    });

    test('a tap outside every annotation selects nothing', () {
      final hit = annotationAtPoint(
        const Offset(500, 100),
        annotations: [
          box(7, const TextRect(left: 10, bottom: 20, right: 50, top: 80)),
        ],
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

      expect(hit, isNull);
    });

    // A large rectangle must not swallow the small highlight drawn on top.
    test('overlapping annotations resolve smallest-area first', () {
      final hit = annotationAtPoint(
        const Offset(30, 792),
        annotations: [
          box(7, const TextRect(left: 0, bottom: 0, right: 500, top: 800)),
          box(8, const TextRect(left: 10, bottom: 20, right: 50, top: 80)),
        ],
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

      expect(hit, 8);
    });
  });

  group('moving', () {
    const target = TextRect(left: 200, bottom: 300, right: 300, top: 400);

    test('moving the selection stages a rect', () {
      c()
        ..loadInto([saved(7)])
        ..select(7)
        ..moveSelected(target);

      expect(s().session.moved[7], target);
    });

    test('moving with nothing selected does nothing', () {
      c()
        ..loadInto([saved(7)])
        ..moveSelected(target);

      expect(s().session.isDirty, isFalse);
    });

    // The selection outline must follow the annotation to its new home, or the
    // user cannot tell the move registered.
    test('the annotation stays selected after a move', () {
      c()
        ..loadInto([saved(7)])
        ..select(7)
        ..moveSelected(target);

      expect(s().selectedObjectNumber, 7);
    });
  });
}
