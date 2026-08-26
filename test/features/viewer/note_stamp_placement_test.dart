import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationController c() =>
      container.read(annotationSessionProvider.notifier);
  AnnotationState s() => container.read(annotationSessionProvider);

  test('placing a note stages one annotation with its text', () {
    c().addNote(
      pageIndex: 0,
      anchorPt: const PdfPoint(100, 700),
      contents: 'Check this',
    );

    final note = s().session.annotations.single as StickyNote;
    expect(note.contents, 'Check this');
    expect(note.anchorPt.x, 100);
  });

  // An empty note is invisible in the popup and clutters the page with an icon
  // that says nothing.
  test('an empty note is not staged', () {
    c().addNote(
      pageIndex: 0,
      anchorPt: const PdfPoint(100, 700),
      contents: '   ',
    );

    expect(s().session.annotations, isEmpty);
  });

  test('placing a stamp stages one annotation with its preset', () {
    c().addStamp(
      preset: StampPreset.approved,
      pageIndex: 1,
      anchorPt: const PdfPoint(50, 500),
    );

    final stamp = s().session.annotations.single as Stamp;
    expect(stamp.preset, StampPreset.approved);
    expect(stamp.pageIndex, 1);
  });

  test('undo removes a placed stamp', () {
    c().addStamp(
      preset: StampPreset.draft,
      pageIndex: 0,
      anchorPt: const PdfPoint(50, 500),
    );
    c().undo();

    expect(s().session.annotations, isEmpty);
  });

  test('notes and stamps share the session with drawings', () {
    c()
      ..addNote(
        pageIndex: 0,
        anchorPt: const PdfPoint(100, 700),
        contents: 'Check',
      )
      ..addStamp(
        preset: StampPreset.urgent,
        pageIndex: 0,
        anchorPt: const PdfPoint(200, 700),
      );

    expect(s().session.annotations, hasLength(2));
    expect(s().session.annotationsOnPage(0), hasLength(2));
  });
}
