import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation_edit_session.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/repositories/annotation_edit_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final annotationEditRepositoryProvider = Provider<AnnotationEditRepository>(
  (ref) => throw UnimplementedError(
    'annotationEditRepositoryProvider must be overridden',
  ),
);

class AnnotationEditState {
  const AnnotationEditState({
    required this.session,
    required this.busy,
    this.selectedObjectNumber,
  });

  final AnnotationEditSession session;
  final bool busy;
  final int? selectedObjectNumber;

  AnnotationEditState copyWith({
    bool? busy,
    int? selectedObjectNumber,
    bool clearSelection = false,
  }) => AnnotationEditState(
    session: session,
    busy: busy ?? this.busy,
    selectedObjectNumber: clearSelection
        ? null
        : selectedObjectNumber ?? this.selectedObjectNumber,
  );
}

final annotationEditProvider =
    NotifierProvider<AnnotationEditController, AnnotationEditState>(
      AnnotationEditController.new,
    );

class AnnotationEditController extends Notifier<AnnotationEditState> {
  @override
  AnnotationEditState build() => AnnotationEditState(
    session: AnnotationEditSession(const []),
    busy: false,
  );

  /// The session mutates in place, so emit a new state object to notify
  /// listeners - the same pattern AnnotationController uses.
  void _touch() => state = state.copyWith();

  Future<void> load(int documentId) async {
    final found = await ref
        .read(annotationEditRepositoryProvider)
        .load(documentId);
    loadInto(found);
  }

  void loadInto(List<SavedAnnotation> annotations) {
    state = AnnotationEditState(
      session: AnnotationEditSession(annotations),
      busy: false,
    );
  }

  void select(int? objectNumber) {
    state = objectNumber == null
        ? state.copyWith(clearSelection: true)
        : state.copyWith(selectedObjectNumber: objectNumber);
  }

  void deleteSelected() {
    final selected = state.selectedObjectNumber;
    if (selected == null) return;
    state.session.delete(selected);
    // A deleted annotation cannot stay selected: it is gone from the list.
    state = state.copyWith(clearSelection: true);
  }

  void restyleSelected(AnnotationStyle style) {
    final selected = state.selectedObjectNumber;
    if (selected == null) return;
    state.session.restyle(selected, style);
    _touch();
  }

  /// Stages a new rect for the selection. The selection is kept: the outline
  /// must follow the annotation, or the user cannot tell the move registered.
  void moveSelected(TextRect rect) {
    final selected = state.selectedObjectNumber;
    if (selected == null) return;
    state.session.moveTo(selected, rect);
    _touch();
  }

  void undo() {
    state.session.undo();
    _touch();
  }

  void reset() {
    state = AnnotationEditState(
      session: AnnotationEditSession(const []),
      busy: false,
    );
  }

  void setBusy(bool value) => state = state.copyWith(busy: value);
}
