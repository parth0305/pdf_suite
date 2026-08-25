import 'package:folio/domain/annotations/annotation.dart';

/// Annotations staged for writing.
///
/// Holds text markup and drawings together, so one undo stack and one Save
/// serve both. Nothing touches a PDF until the caller saves, so undo is a
/// stack of in-memory snapshots and an abandoned session leaves no files
/// behind. The same shape as PageEditSession, deliberately.
class AnnotationSession {
  List<Annotation> _annotations = [];
  final List<List<Annotation>> _undo = [];
  final List<List<Annotation>> _redo = [];

  List<Annotation> get annotations => List.unmodifiable(_annotations);

  bool get isEmpty => _annotations.isEmpty;
  bool get isDirty => _annotations.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  List<Annotation> annotationsOnPage(int pageIndex) =>
      _annotations.where((a) => a.pageIndex == pageIndex).toList();

  void _mutate(void Function(List<Annotation>) change) {
    final snapshot = List.of(_annotations);
    final working = List.of(_annotations);
    change(working);
    _undo.add(snapshot);
    _redo.clear();
    _annotations = working;
  }

  void add(Annotation annotation) => _mutate((list) => list.add(annotation));

  void removeAt(int index) {
    RangeError.checkValidIndex(index, _annotations, 'index');
    _mutate((list) => list.removeAt(index));
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(List.of(_annotations));
    _annotations = _undo.removeLast();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(List.of(_annotations));
    _annotations = _redo.removeLast();
  }
}
