import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/features/automation/automation_providers.dart';
import 'package:folio/domain/models/library_collection.dart';
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

    await _mutate(() async {
      final imported = await _repo.importFile(
        file.path,
        displayName: file.name,
      );
      // Rules run after the document is safely in the library, never as part
      // of importing it: a rule that fails must not lose the import.
      await ref.read(automationRepositoryProvider).runOnImport(imported);
    });
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

  Future<void> moveToCollection(int docId, int? collectionId) =>
      _mutate(() => _repo.moveToCollection(docId, collectionId));

  Future<void> exportCopy(int docId, String destinationPath) =>
      _mutate(() => _repo.exportCopy(docId, destinationPath));
}

final collectionsControllerProvider =
    AsyncNotifierProvider<CollectionsController, List<LibraryCollection>>(
      CollectionsController.new,
    );

class CollectionsController extends AsyncNotifier<List<LibraryCollection>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  Future<List<LibraryCollection>> build() => _repo.collections();

  Future<void> _mutate(Future<void> Function() action) async {
    state = await AsyncValue.guard(() async {
      await action();
      return _repo.collections();
    });
    // Documents carry a collectionId, so the library list must reload too.
    await ref.read(libraryControllerProvider.notifier).refresh();
  }

  Future<void> create(String name) =>
      _mutate(() => _repo.createCollection(name).then((_) {}));

  Future<void> rename(int id, String name) =>
      _mutate(() => _repo.renameCollection(id, name));

  Future<void> remove(int id) async {
    await _mutate(() => _repo.deleteCollection(id));
    // A deleted folder cannot stay selected.
    if (ref.read(selectedCollectionProvider) == id) {
      ref.read(selectedCollectionProvider.notifier).value = null;
    }
  }
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

/// Documents picked in library selection mode, for multi-document operations.
final librarySelectionProvider =
    NotifierProvider<_ValueNotifier<Set<int>>, Set<int>>(
      () => _ValueNotifier(const {}),
    );

/// Whether the library is in multi-select mode.
final librarySelectModeProvider = NotifierProvider<_ValueNotifier<bool>, bool>(
  () => _ValueNotifier(false),
);

/// Null means "All": no folder filter at all, not "the root folder".
final selectedCollectionProvider = NotifierProvider<_ValueNotifier<int?>, int?>(
  () => _ValueNotifier(null),
);

/// Documents after tab selection, filtering and sorting - ready to render.
final visibleDocumentsProvider = Provider<AsyncValue<List<LibraryDocument>>>((
  ref,
) {
  final docs = ref.watch(libraryControllerProvider);
  final tab = ref.watch(selectedTabProvider);
  final collection = ref.watch(selectedCollectionProvider);
  final query = ref.watch(searchQueryProvider);
  final field = ref.watch(sortFieldProvider);
  final ascending = ref.watch(sortAscendingProvider);

  return docs.whenData((items) {
    final inCollection = collection == null
        ? items
        : items.where((d) => d.collectionId == collection).toList();

    final scoped = switch (tab) {
      LibraryTab.all => inCollection,
      LibraryTab.recents =>
        inCollection.where((d) => d.lastOpenedAt != null).toList(),
      LibraryTab.favorites => inCollection.where((d) => d.isFavorite).toList(),
    };
    return sortDocuments(
      filterDocuments(scoped, query),
      field: tab == LibraryTab.recents ? SortField.dateOpened : field,
      ascending: tab == LibraryTab.recents ? false : ascending,
    );
  });
});
