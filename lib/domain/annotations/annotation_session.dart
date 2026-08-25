import 'package:folio/domain/annotations/text_markup.dart';

/// Markup staged for writing.
///
/// Nothing touches a PDF until the caller saves, so undo is a stack of
/// in-memory snapshots and an abandoned session leaves no files behind. The
/// same shape as PageEditSession, deliberately.
class AnnotationSession {
  List<TextMarkup> _markups = [];
  final List<List<TextMarkup>> _undo = [];
  final List<List<TextMarkup>> _redo = [];

  List<TextMarkup> get markups => List.unmodifiable(_markups);

  bool get isEmpty => _markups.isEmpty;
  bool get isDirty => _markups.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  List<TextMarkup> markupsOnPage(int pageIndex) =>
      _markups.where((m) => m.pageIndex == pageIndex).toList();

  void _mutate(void Function(List<TextMarkup>) change) {
    final snapshot = List.of(_markups);
    final working = List.of(_markups);
    change(working);
    _undo.add(snapshot);
    _redo.clear();
    _markups = working;
  }

  void add(TextMarkup markup) => _mutate((list) => list.add(markup));

  void removeAt(int index) {
    RangeError.checkValidIndex(index, _markups, 'index');
    _mutate((list) => list.removeAt(index));
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(List.of(_markups));
    _markups = _undo.removeLast();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(List.of(_markups));
    _markups = _redo.removeLast();
  }
}
