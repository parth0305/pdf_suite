import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation_session.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/stroke_smoothing.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/domain/signatures/signature_geometry.dart';
import 'package:folio/domain/annotations/quad_merge.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/repositories/annotation_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final annotationRepositoryProvider = Provider<AnnotationRepository>(
  (ref) => throw UnimplementedError(
    'annotationRepositoryProvider must be overridden',
  ),
);

class AnnotationState {
  const AnnotationState({
    required this.session,
    required this.busy,
    this.liveStroke = const [],
  });

  final AnnotationSession session;
  final bool busy;

  /// Canvas-space points of the stroke currently under the finger. Kept in
  /// canvas space so the preview can be painted without converting back.
  final List<Offset> liveStroke;

  AnnotationState copyWith({bool? busy, List<Offset>? liveStroke}) =>
      AnnotationState(
        session: session,
        busy: busy ?? this.busy,
        liveStroke: liveStroke ?? this.liveStroke,
      );
}

final annotationSessionProvider =
    NotifierProvider<AnnotationController, AnnotationState>(
      AnnotationController.new,
    );

class AnnotationController extends Notifier<AnnotationState> {
  @override
  AnnotationState build() =>
      AnnotationState(session: AnnotationSession(), busy: false);

  /// The session mutates in place, so emit a new state object to notify
  /// listeners - the same pattern PageSessionController uses.
  void _touch() => state = state.copyWith();

  /// Stages markup for a selection.
  ///
  /// [charRects] are per-character boxes straight from `PageText.charRects`;
  /// they are merged into one quad per line here, because emitting a quad per
  /// character would produce thousands of numbers for an ordinary selection.
  void addMarkup({
    required MarkupKind kind,
    required int pageIndex,
    required List<TextRect> charRects,
  }) {
    final quads = mergeIntoLineQuads(charRects);
    if (quads.isEmpty) return;

    state.session.add(
      TextMarkup(kind: kind, pageIndex: pageIndex, quads: quads),
    );
    _touch();
  }

  void beginStroke(Offset point) {
    state = state.copyWith(liveStroke: [point]);
  }

  void extendStroke(Offset point) {
    state = state.copyWith(liveStroke: [...state.liveStroke, point]);
  }

  /// Commits the live stroke as an annotation in PDF space.
  ///
  /// Shapes keep only the first and last point - the drag's two corners -
  /// while ink keeps the thinned path.
  void endStroke({
    required DrawingKind tool,
    required int pageIndex,
    required Rect pageRect,
    required double pageWidthPt,
    required double pageHeightPt,
    int colorArgb = 0xFF000000,
    double strokeWidth = 2,
  }) {
    final live = state.liveStroke;
    // A tap with no drag would otherwise leave an invisible dot behind.
    if (live.length < 2) {
      state = state.copyWith(liveStroke: const []);
      return;
    }

    final canvasPoints = tool == DrawingKind.ink
        ? live
        : [live.first, live.last];

    final pdfPoints = [
      for (final p in canvasPoints)
        canvasToPdf(
          p,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
    ];

    state.session.add(
      DrawingAnnotation(
        kind: tool,
        pageIndex: pageIndex,
        strokes: [tool == DrawingKind.ink ? thinSamples(pdfPoints) : pdfPoints],
        colorArgb: colorArgb,
        strokeWidth: strokeWidth,
      ),
    );
    state = state.copyWith(liveStroke: const []);
  }

  /// Stages a saved signature fitted into [box].
  ///
  /// One annotation carrying every stroke, not one per stroke: deleting a
  /// signature must remove the whole thing.
  void addSignature({
    required SavedSignature signature,
    required int pageIndex,
    required TextRect box,
    int colorArgb = 0xFF000000,
    double strokeWidth = 2,
  }) {
    // A photographed signature is pixels, not strokes: it becomes an image
    // annotation with the transparency mask that hides its paper.
    if (signature.kind == SignatureKind.photo) {
      if (!signature.isPlaceable) return;

      state.session.add(
        ImageAnnotation(
          pageIndex: pageIndex,
          rect: box,
          rgba: signature.imageRgba!,
          pixelWidth: signature.pixelWidth!,
          pixelHeight: signature.pixelHeight!,
        ),
      );
      _touch();
      return;
    }

    final strokes = placeSignature(signature, box: box);
    if (strokes.isEmpty) return;

    state.session.add(
      DrawingAnnotation(
        kind: DrawingKind.ink,
        pageIndex: pageIndex,
        strokes: strokes,
        colorArgb: colorArgb,
        strokeWidth: strokeWidth,
      ),
    );
    _touch();
  }

  /// Stages a sticky note. Empty text is refused: an icon that says nothing
  /// only clutters the page.
  void addNote({
    required int pageIndex,
    required PdfPoint anchorPt,
    required String contents,
  }) {
    if (contents.trim().isEmpty) return;

    state.session.add(
      StickyNote(
        pageIndex: pageIndex,
        anchorPt: anchorPt,
        contents: contents.trim(),
      ),
    );
    _touch();
  }

  void addStamp({
    required StampPreset preset,
    required int pageIndex,
    required PdfPoint anchorPt,
    String? customLabel,
  }) {
    state.session.add(
      Stamp(
        preset: preset,
        pageIndex: pageIndex,
        anchorPt: anchorPt,
        customLabel: customLabel,
      ),
    );
    _touch();
  }

  /// Stages an image fitted into [box].
  void addImage({
    required int pageIndex,
    required TextRect box,
    required List<int> rgba,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    if (rgba.isEmpty || pixelWidth <= 0 || pixelHeight <= 0) return;

    state.session.add(
      ImageAnnotation(
        pageIndex: pageIndex,
        rect: box,
        rgba: rgba,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      ),
    );
    _touch();
  }

  void undo() {
    state.session.undo();
    _touch();
  }

  void reset() {
    state = AnnotationState(session: AnnotationSession(), busy: false);
  }

  void setBusy(bool value) => state = state.copyWith(busy: value);
}
