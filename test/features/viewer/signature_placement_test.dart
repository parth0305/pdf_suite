import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

const two = SavedSignature(
  id: 1,
  label: 'Full',
  strokes: [
    [PdfPoint(0, 0), PdfPoint(0.4, 1)],
    [PdfPoint(0.6, 0), PdfPoint(1, 1)],
  ],
  aspectRatio: 2,
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationController c() =>
      container.read(annotationSessionProvider.notifier);
  AnnotationState s() => container.read(annotationSessionProvider);

  // One annotation, not one per stroke: deleting a signature must remove the
  // whole thing rather than leaving the other strokes behind.
  test('placing a signature stages exactly one annotation', () {
    c().addSignature(
      signature: two,
      pageIndex: 0,
      box: const TextRect(left: 100, bottom: 100, right: 300, top: 200),
    );

    expect(s().session.annotations, hasLength(1));
  });

  test('the annotation is ink and keeps both strokes', () {
    c().addSignature(
      signature: two,
      pageIndex: 0,
      box: const TextRect(left: 100, bottom: 100, right: 300, top: 200),
    );

    final ink = s().session.annotations.single as DrawingAnnotation;
    expect(ink.kind, DrawingKind.ink);
    expect(ink.strokes, hasLength(2));
  });

  test('the strokes land inside the box', () {
    c().addSignature(
      signature: two,
      pageIndex: 0,
      box: const TextRect(left: 100, bottom: 100, right: 300, top: 200),
    );

    final ink = s().session.annotations.single as DrawingAnnotation;
    final flat = ink.strokes.expand((st) => st).toList();
    expect(flat.every((p) => p.x >= 100 && p.x <= 300), isTrue);
    expect(flat.every((p) => p.y >= 100 && p.y <= 200), isTrue);
  });

  test('placing on page 2 records page 2', () {
    c().addSignature(
      signature: two,
      pageIndex: 2,
      box: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
    );

    expect(s().session.annotations.single.pageIndex, 2);
  });

  test('undo removes the whole signature', () {
    c().addSignature(
      signature: two,
      pageIndex: 0,
      box: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
    );
    c().undo();

    expect(s().session.annotations, isEmpty);
  });
}
