import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/editing/page_edit_session.dart';
import 'package:folio/domain/repositories/page_operations_repository.dart';

/// Overridden at app start with the real implementation, and in tests with a
/// fake. Reading it unoverridden is a programming error, not a runtime state.
final pageOperationsRepositoryProvider = Provider<PageOperationsRepository>(
  (ref) => throw UnimplementedError(
    'pageOperationsRepositoryProvider must be overridden',
  ),
);

class PageSessionState {
  const PageSessionState({
    required this.session,
    required this.selection,
    required this.busy,
  });

  final PageEditSession session;
  final Set<int> selection;
  final bool busy;

  PageSessionState copyWith({
    PageEditSession? session,
    Set<int>? selection,
    bool? busy,
  }) => PageSessionState(
    session: session ?? this.session,
    selection: selection ?? this.selection,
    busy: busy ?? this.busy,
  );
}

final pageSessionProvider =
    NotifierProvider<PageSessionController, PageSessionState>(
      PageSessionController.new,
    );

class PageSessionController extends Notifier<PageSessionState> {
  @override
  PageSessionState build() => PageSessionState(
    session: PageEditSession.fromDocument(0, 0),
    selection: const {},
    busy: false,
  );

  void start({required int documentId, required int pageCount}) {
    state = PageSessionState(
      session: PageEditSession.fromDocument(documentId, pageCount),
      selection: const {},
      busy: false,
    );
  }

  /// The session mutates in place, so emit a new state object to notify
  /// listeners without pretending the session itself is immutable.
  void _touch({Set<int>? selection}) {
    state = state.copyWith(selection: selection ?? state.selection);
  }

  void toggleSelection(int index) {
    final next = Set<int>.of(state.selection);
    if (next.contains(index)) {
      next.remove(index);
    } else {
      next.add(index);
    }
    _touch(selection: next);
  }

  void selectAll() => _touch(
    selection: {for (var i = 0; i < state.session.slots.length; i++) i},
  );

  void clearSelection() => _touch(selection: const {});

  void move(int from, int to) {
    state.session.move(from, to);
    // Indices shift on reorder, so a stale selection would highlight the
    // wrong pages.
    _touch(selection: const {});
  }

  void deleteSelected() {
    if (state.selection.isEmpty) return;
    // Refuse rather than produce a zero-page document, which is not a valid
    // PDF and would fail to reopen.
    if (state.selection.length >= state.session.slots.length) return;

    state.session.removeAt(state.selection);
    _touch(selection: const {});
  }

  void duplicateSelected() {
    if (state.selection.isEmpty) return;
    state.session.duplicateAt(state.selection);
    _touch(selection: const {});
  }

  void rotateSelected(int quarterTurns) {
    if (state.selection.isEmpty) return;
    state.session.rotate(state.selection, quarterTurns: quarterTurns);
    _touch();
  }

  void insertFrom(int documentId, int pageCount, {required int at}) {
    state.session.insertFrom(documentId, pageCount, at: at);
    _touch(selection: const {});
  }

  void undo() {
    state.session.undo();
    _touch(selection: const {});
  }

  void redo() {
    state.session.redo();
    _touch(selection: const {});
  }

  void setBusy(bool value) => state = state.copyWith(busy: value);
}
