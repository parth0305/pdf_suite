import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

const quad = TextRect(left: 60, top: 712, right: 120, bottom: 700);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationController controller() =>
      container.read(annotationSessionProvider.notifier);
  AnnotationState state() => container.read(annotationSessionProvider);

  test('starts empty', () {
    expect(state().session.annotations, isEmpty);
    expect(state().session.isDirty, isFalse);
  });

  test('adding markup from a selection stages it', () {
    controller().addMarkup(
      kind: MarkupKind.highlight,
      pageIndex: 0,
      charRects: const [quad],
    );

    expect(state().session.annotations, hasLength(1));
    expect(
      (state().session.annotations.single as TextMarkup).kind,
      MarkupKind.highlight,
    );
  });

  // The controller merges per-character rects into line quads before staging.
  test('per-character rects are merged into line quads', () {
    controller().addMarkup(
      kind: MarkupKind.highlight,
      pageIndex: 0,
      charRects: const [
        TextRect(left: 60, top: 712, right: 67, bottom: 700),
        TextRect(left: 67, top: 712, right: 74, bottom: 700),
        TextRect(left: 74, top: 712, right: 81, bottom: 700),
      ],
    );

    expect(
      (state().session.annotations.single as TextMarkup).quads,
      hasLength(1),
    );
    expect(
      (state().session.annotations.single as TextMarkup).quads.single.right,
      81,
    );
  });

  test('an empty selection adds nothing', () {
    controller().addMarkup(
      kind: MarkupKind.highlight,
      pageIndex: 0,
      charRects: const [],
    );
    expect(state().session.annotations, isEmpty);
  });

  test('undo removes the last markup', () {
    controller()
      ..addMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        charRects: const [quad],
      )
      ..undo();

    expect(state().session.annotations, isEmpty);
  });

  test('reset clears the session', () {
    controller()
      ..addMarkup(
        kind: MarkupKind.underline,
        pageIndex: 0,
        charRects: const [quad],
      )
      ..reset();

    expect(state().session.annotations, isEmpty);
    expect(state().session.canUndo, isFalse);
  });
}
