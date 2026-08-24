import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/document_sorter.dart';

/// Overridden at app start with the real implementation, and in tests with a
/// fake. Reading it unoverridden is a programming error, not a runtime state.
final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) =>
      throw UnimplementedError('libraryRepositoryProvider must be overridden'),
);

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, List<LibraryDocument>>(
      LibraryController.new,
    );

class LibraryController extends AsyncNotifier<List<LibraryDocument>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  Future<List<LibraryDocument>> build() => _repo.all();

  Future<void> refresh() async {
    state = await AsyncValue.guard(_repo.all);
  }

  /// Runs [action] then refreshes, surfacing any AppFailure through the
  /// AsyncValue rather than as an uncaught exception.
  Future<void> _mutate(Future<void> Function() action) async {
    state = await AsyncValue.guard(() async {
      await action();
      return _repo.all();
    });
  }

  Future<void> importFromPicker() async {
    const typeGroup = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
      mimeTypes: ['application/pdf'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    await _mutate(() => _repo.importFile(file.path, displayName: file.name));
  }

  Future<void> toggleFavorite(int id) async {
    final doc = (state.value ?? const []).firstWhere((d) => d.id == id);
    await _mutate(() => _repo.setFavorite(id, !doc.isFavorite));
  }

  Future<void> remove(int id) => _mutate(() => _repo.delete(id));

  Future<void> renameDocument(int id, String name) =>
      _mutate(() => _repo.rename(id, name));

  Future<void> duplicateDocument(int id) =>
      _mutate(() => _repo.duplicate(id).then((_) {}));

  Future<void> markOpened(int id) => _mutate(() => _repo.markOpened(id));
}

/// Which library tab is showing.
enum LibraryTab { all, recents, favorites }

class _ValueNotifier<T> extends Notifier<T> {
  _ValueNotifier(this._initial);
  final T _initial;

  @override
  T build() => _initial;

  set value(T next) => state = next;
}

final selectedTabProvider =
    NotifierProvider<_ValueNotifier<LibraryTab>, LibraryTab>(
      () => _ValueNotifier(LibraryTab.all),
    );
final sortFieldProvider =
    NotifierProvider<_ValueNotifier<SortField>, SortField>(
      () => _ValueNotifier(SortField.dateAdded),
    );
final sortAscendingProvider = NotifierProvider<_ValueNotifier<bool>, bool>(
  () => _ValueNotifier(false),
);
final searchQueryProvider = NotifierProvider<_ValueNotifier<String>, String>(
  () => _ValueNotifier(''),
);

/// Documents after tab selection, filtering and sorting - ready to render.
final visibleDocumentsProvider = Provider<AsyncValue<List<LibraryDocument>>>((
  ref,
) {
  final docs = ref.watch(libraryControllerProvider);
  final tab = ref.watch(selectedTabProvider);
  final query = ref.watch(searchQueryProvider);
  final field = ref.watch(sortFieldProvider);
  final ascending = ref.watch(sortAscendingProvider);

  return docs.whenData((items) {
    final scoped = switch (tab) {
      LibraryTab.all => items,
      LibraryTab.recents => items.where((d) => d.lastOpenedAt != null).toList(),
      LibraryTab.favorites => items.where((d) => d.isFavorite).toList(),
    };
    return sortDocuments(
      filterDocuments(scoped, query),
      field: tab == LibraryTab.recents ? SortField.dateOpened : field,
      ascending: tab == LibraryTab.recents ? false : ascending,
    );
  });
});
