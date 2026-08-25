import 'package:folio/domain/editing/page_slot.dart';

/// A staged set of page edits.
///
/// Operations manipulate an in-memory list of [PageSlot]; no PDF is touched
/// until the caller materialises the result. That is what makes this logic
/// unit-testable with no simulator, and what lets undo be a stack of snapshots
/// rather than a history of file writes.
class PageEditSession {
  PageEditSession._(this._slots);

  factory PageEditSession.fromDocument(int documentId, int pageCount) {
    return PageEditSession._([
      for (var i = 0; i < pageCount; i++)
        PageSlot(sourceDocumentId: documentId, sourcePageIndex: i),
    ]);
  }

  List<PageSlot> _slots;

  /// Whole-list snapshots. The lists are tiny - one small value object per
  /// page - and snapshotting sidesteps a class of bugs that inverse-operation
  /// command objects invite.
  final List<List<PageSlot>> _undoStack = [];
  final List<List<PageSlot>> _redoStack = [];

  late final List<PageSlot> _original = List.of(_slots);

  List<PageSlot> get slots => List.unmodifiable(_slots);

  bool get isEmpty => _slots.isEmpty;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// True when the current order differs from the session's starting point.
  bool get isDirty {
    if (_slots.length != _original.length) return true;
    for (var i = 0; i < _slots.length; i++) {
      if (_slots[i] != _original[i]) return true;
    }
    return false;
  }

  /// Snapshots the current state, runs [change], and clears the redo branch.
  void _mutate(void Function(List<PageSlot> slots) change) {
    final snapshot = List.of(_slots);
    final working = List.of(_slots);
    change(working);
    _undoStack.add(snapshot);
    _redoStack.clear();
    _slots = working;
  }

  void move(int from, int to) {
    RangeError.checkValidIndex(from, _slots, 'from');
    RangeError.checkValidIndex(to, _slots, 'to');
    // A drag that lands where it started must not dirty the session.
    if (from == to) return;

    _mutate((slots) {
      final slot = slots.removeAt(from);
      slots.insert(to, slot);
    });
  }

  void removeAt(Iterable<int> indices) {
    final targets = indices.toSet();
    if (targets.isEmpty) return;
    for (final i in targets) {
      RangeError.checkValidIndex(i, _slots, 'index');
    }

    _mutate((slots) {
      // Descending order, so removing one index cannot shift the next.
      final ordered = targets.toList()..sort((a, b) => b.compareTo(a));
      for (final i in ordered) {
        slots.removeAt(i);
      }
    });
  }

  void duplicateAt(Iterable<int> indices) {
    final targets = indices.toSet();
    if (targets.isEmpty) return;
    for (final i in targets) {
      RangeError.checkValidIndex(i, _slots, 'index');
    }

    _mutate((slots) {
      // Descending, so each insertion cannot shift a not-yet-processed index.
      final ordered = targets.toList()..sort((a, b) => b.compareTo(a));
      for (final i in ordered) {
        slots.insert(i + 1, slots[i]);
      }
    });
  }

  void rotate(Iterable<int> indices, {required int quarterTurns}) {
    final targets = indices.toSet();
    if (targets.isEmpty) return;
    for (final i in targets) {
      RangeError.checkValidIndex(i, _slots, 'index');
    }

    _mutate((slots) {
      for (final i in targets) {
        // Each page advances from its own current rotation, so a mixed
        // selection stays mixed rather than flattening to one value.
        slots[i] = slots[i].rotatedBy(quarterTurns);
      }
    });
  }

  void insertFrom(int documentId, int pageCount, {required int at}) {
    if (at < 0 || at > _slots.length) {
      throw RangeError.range(at, 0, _slots.length, 'at');
    }

    _mutate((slots) {
      slots.insertAll(at, [
        for (var i = 0; i < pageCount; i++)
          PageSlot(sourceDocumentId: documentId, sourcePageIndex: i),
      ]);
    });
  }

  /// Reads a selection out without changing the session: extraction produces a
  /// separate document and leaves the one being edited alone.
  List<PageSlot> extract(Iterable<int> indices) {
    final targets = indices.toSet();
    for (final i in targets) {
      RangeError.checkValidIndex(i, _slots, 'index');
    }
    // List order, not selection order, so the output matches what is on screen.
    final ordered = targets.toList()..sort();
    return [for (final i in ordered) _slots[i]];
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.of(_slots));
    _slots = _undoStack.removeLast();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.of(_slots));
    _slots = _redoStack.removeLast();
  }
}
