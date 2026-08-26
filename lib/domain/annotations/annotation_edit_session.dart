import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// Edits staged against annotations already saved in a document.
///
/// Nothing touches the file until the caller saves, so undo is a stack of
/// in-memory snapshots and an abandoned session leaves the document untouched.
/// The same shape as AnnotationSession and PageEditSession, deliberately.
class AnnotationEditSession {
  AnnotationEditSession(List<SavedAnnotation> loaded)
    : _loaded = List.unmodifiable(loaded);

  final List<SavedAnnotation> _loaded;

  Set<int> _deleted = {};
  Map<int, AnnotationStyle> _restyled = {};
  Map<int, TextRect> _moved = {};
  final List<
    ({
      Set<int> deleted,
      Map<int, AnnotationStyle> restyled,
      Map<int, TextRect> moved,
    })
  >
  _undo = [];

  /// Everything still present, in load order. A deleted annotation leaves this
  /// list immediately, so the UI reflects the staged state.
  List<SavedAnnotation> get annotations => List.unmodifiable(
    _loaded.where((a) => !_deleted.contains(a.objectNumber)),
  );

  List<SavedAnnotation> onPage(int pageIndex) =>
      List.unmodifiable(annotations.where((a) => a.pageIndex == pageIndex));

  Set<int> get deleted => Set.unmodifiable(_deleted);
  Map<int, AnnotationStyle> get restyled => Map.unmodifiable(_restyled);
  Map<int, TextRect> get moved => Map.unmodifiable(_moved);

  AnnotationStyle? styleOf(int objectNumber) => _restyled[objectNumber];

  bool get isDirty =>
      _deleted.isNotEmpty || _restyled.isNotEmpty || _moved.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;

  void _snapshot() {
    _undo.add((
      deleted: Set.of(_deleted),
      restyled: Map.of(_restyled),
      moved: Map.of(_moved),
    ));
  }

  void delete(int objectNumber) {
    _snapshot();
    _deleted = {..._deleted, objectNumber};
    // A style staged for something about to be unreferenced is dead weight,
    // and would emit an override for an annotation nothing points at.
    _restyled = {..._restyled}..remove(objectNumber);
    _moved = {..._moved}..remove(objectNumber);
  }

  /// Stages a new rect for [objectNumber].
  void moveTo(int objectNumber, TextRect rect) {
    _snapshot();
    _moved = {..._moved, objectNumber: rect};
  }

  void restyle(int objectNumber, AnnotationStyle style) {
    _snapshot();
    _restyled = {..._restyled, objectNumber: style};
  }

  void undo() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    _deleted = previous.deleted;
    _restyled = previous.restyled;
    _moved = previous.moved;
  }
}
