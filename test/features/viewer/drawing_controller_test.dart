import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

const pageRect = Rect.fromLTWH(0, 0, 595, 842);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationController c() =>
      container.read(annotationSessionProvider.notifier);
  AnnotationState s() => container.read(annotationSessionProvider);

  test('a stroke in progress is visible before it is committed', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..extendStroke(const Offset(40, 40));

    expect(s().liveStroke, hasLength(2));
    expect(s().session.annotations, isEmpty, reason: 'not committed yet');
  });

  test('ending a stroke commits it and clears the live points', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..extendStroke(const Offset(40, 40))
      ..endStroke(
        tool: DrawingKind.ink,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

    expect(s().liveStroke, isEmpty);
    expect(s().session.annotations, hasLength(1));
  });

  // A tap with no drag must not leave an invisible dot annotation behind.
  test('a stroke of one point commits nothing', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..endStroke(
        tool: DrawingKind.ink,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

    expect(s().session.annotations, isEmpty);
  });

  test('a shape keeps only its first and last point', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..extendStroke(const Offset(25, 25))
      ..extendStroke(const Offset(40, 40))
      ..endStroke(
        tool: DrawingKind.rectangle,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

    final drawing = s().session.annotations.single as DrawingAnnotation;
    expect(drawing.points, hasLength(2));
  });

  test('committed points are in PDF space, not canvas space', () {
    c()
      ..beginStroke(const Offset(100, 10))
      ..extendStroke(const Offset(200, 20))
      ..endStroke(
        tool: DrawingKind.line,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

    final drawing = s().session.annotations.single as DrawingAnnotation;
    // Canvas y=10 is near the top, so PDF y must be large.
    expect(drawing.points.first.y, greaterThan(800));
  });

  test('undo removes a committed stroke', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..extendStroke(const Offset(40, 40))
      ..endStroke(
        tool: DrawingKind.ink,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );
    c().undo();

    expect(s().session.annotations, isEmpty);
  });
}
