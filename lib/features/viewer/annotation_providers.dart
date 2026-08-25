import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation_session.dart';
import 'package:folio/domain/annotations/quad_merge.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/repositories/annotation_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final annotationRepositoryProvider = Provider<AnnotationRepository>(
  (ref) => throw UnimplementedError(
    'annotationRepositoryProvider must be overridden',
  ),
);

class AnnotationState {
  const AnnotationState({required this.session, required this.busy});

  final AnnotationSession session;
  final bool busy;

  AnnotationState copyWith({bool? busy}) =>
      AnnotationState(session: session, busy: busy ?? this.busy);
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

  void undo() {
    state.session.undo();
    _touch();
  }

  void reset() {
    state = AnnotationState(session: AnnotationSession(), busy: false);
  }

  void setBusy(bool value) => state = state.copyWith(busy: value);
}
