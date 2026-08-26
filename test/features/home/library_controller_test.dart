import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_collection.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/features/home/providers.dart';

class _FakeRepo implements LibraryRepository {
  final List<LibraryDocument> docs = [];
  int _nextId = 1;

  LibraryDocument _make(String name) => LibraryDocument(
    id: _nextId++,
    ref: ManagedRef(relativePath: name, contentHash: name),
    displayName: name,
    sizeBytes: 100,
    addedAt: DateTime(2026, 8, 24),
    isFavorite: false,
  );

  void seed(String name) => docs.add(_make(name));

  @override
  Future<List<LibraryDocument>> all() async => List.of(docs);

  @override
  Future<void> setFavorite(int id, bool value) async {
    final i = docs.indexWhere((d) => d.id == id);
    docs[i] = docs[i].copyWith(isFavorite: value);
  }

  @override
  Future<void> delete(int id) async => docs.removeWhere((d) => d.id == id);

  @override
  Future<void> rename(int id, String name) async {
    final i = docs.indexWhere((d) => d.id == id);
    docs[i] = docs[i].copyWith(displayName: name);
  }

  @override
  Future<LibraryDocument> importFile(
    String sourcePath, {
    required String displayName,
  }) async {
    final doc = _make(displayName);
    docs.add(doc);
    return doc;
  }

  @override
  Future<List<LibraryDocument>> favorites() async =>
      docs.where((d) => d.isFavorite).toList();

  @override
  Future<List<LibraryDocument>> recents({int limit = 20}) async =>
      docs.where((d) => d.lastOpenedAt != null).toList();

  @override
  Future<void> markOpened(int id) async {
    final i = docs.indexWhere((d) => d.id == id);
    docs[i] = docs[i].copyWith(lastOpenedAt: DateTime(2026, 8, 25));
  }

  @override
  Future<String> resolveReadablePath(LibraryDocument doc) async =>
      doc.displayName;

  @override
  Future<LibraryDocument> openInPlace(
    String pathOrUri, {
    required String displayName,
  }) async => _make(displayName);

  @override
  Future<void> exportCopy(int docId, String destinationPath) async {}

  @override
  Future<void> moveToCollection(int docId, int? collectionId) async {
    final i = docs.indexWhere((d) => d.id == docId);
    docs[i] = collectionId == null
        ? docs[i].copyWith(clearCollection: true)
        : docs[i].copyWith(collectionId: collectionId);
  }

  final List<LibraryCollection> folders = [];
  int _nextFolderId = 1;

  @override
  Future<List<LibraryCollection>> collections() async => List.of(folders);

  @override
  Future<int> createCollection(String name) async {
    final id = _nextFolderId++;
    folders.add(LibraryCollection(id: id, name: name));
    return id;
  }

  @override
  Future<void> renameCollection(int id, String name) async {
    final i = folders.indexWhere((f) => f.id == id);
    folders[i] = LibraryCollection(id: id, name: name);
  }

  @override
  Future<LibraryDocument> registerManaged({
    required String relativePath,
    required String contentHash,
    required String displayName,
    required int sizeBytes,
    bool createdByFolio = false,
  }) async {
    final doc = _make(displayName);
    docs.add(doc);
    return doc;
  }

  @override
  Future<LibraryDocument> replaceManagedContent({
    required int documentId,
    required Uint8List bytes,
  }) async => docs.firstWhere((d) => d.id == documentId);

  @override
  Future<void> deleteCollection(int id) async {
    folders.removeWhere((f) => f.id == id);
    for (var i = 0; i < docs.length; i++) {
      if (docs[i].collectionId == id) {
        docs[i] = docs[i].copyWith(clearCollection: true);
      }
    }
  }

  @override
  Future<LibraryDocument> duplicate(int id) async {
    final doc = _make('copy');
    docs.add(doc);
    return doc;
  }
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo();
    container = ProviderContainer(
      overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() => container.dispose());

  group('LibraryController', () {
    test('loads documents from the repository', () async {
      repo
        ..seed('a.pdf')
        ..seed('b.pdf');
      final docs = await container.read(libraryControllerProvider.future);
      expect(docs, hasLength(2));
    });

    test('toggleFavorite updates the document', () async {
      repo.seed('a.pdf');
      await container.read(libraryControllerProvider.future);

      await container
          .read(libraryControllerProvider.notifier)
          .toggleFavorite(1);
      final docs = await container.read(libraryControllerProvider.future);

      expect(docs.single.isFavorite, isTrue);
    });

    test('toggleFavorite is reversible', () async {
      repo.seed('a.pdf');
      await container.read(libraryControllerProvider.future);
      final n = container.read(libraryControllerProvider.notifier);

      await n.toggleFavorite(1);
      await n.toggleFavorite(1);

      final docs = await container.read(libraryControllerProvider.future);
      expect(docs.single.isFavorite, isFalse);
    });

    test('remove deletes the document', () async {
      repo.seed('a.pdf');
      await container.read(libraryControllerProvider.future);

      await container.read(libraryControllerProvider.notifier).remove(1);
      final docs = await container.read(libraryControllerProvider.future);

      expect(docs, isEmpty);
    });

    test('renameDocument changes the display name', () async {
      repo.seed('old.pdf');
      await container.read(libraryControllerProvider.future);

      await container
          .read(libraryControllerProvider.notifier)
          .renameDocument(1, 'new.pdf');
      final docs = await container.read(libraryControllerProvider.future);

      expect(docs.single.displayName, 'new.pdf');
    });

    test('markOpened moves a document into recents', () async {
      repo.seed('a.pdf');
      await container.read(libraryControllerProvider.future);

      await container.read(libraryControllerProvider.notifier).markOpened(1);
      final docs = await container.read(libraryControllerProvider.future);

      expect(docs.single.lastOpenedAt, isNotNull);
    });
  });

  group('collections', () {
    test('creating a folder makes it available', () async {
      await container.read(collectionsControllerProvider.future);
      await container
          .read(collectionsControllerProvider.notifier)
          .create('Invoices');

      final folders = await container.read(
        collectionsControllerProvider.future,
      );
      expect(folders.single.name, 'Invoices');
    });

    test('moving a document sets its collection', () async {
      repo.seed('a.pdf');
      await container.read(libraryControllerProvider.future);
      await container.read(collectionsControllerProvider.future);
      await container
          .read(collectionsControllerProvider.notifier)
          .create('Invoices');
      final folder = (await container.read(
        collectionsControllerProvider.future,
      )).single;

      await container
          .read(libraryControllerProvider.notifier)
          .moveToCollection(1, folder.id);

      final docs = await container.read(libraryControllerProvider.future);
      expect(docs.single.collectionId, folder.id);
    });

    test('deleting a folder returns its documents to the root', () async {
      repo.seed('a.pdf');
      await container.read(libraryControllerProvider.future);
      await container.read(collectionsControllerProvider.future);
      await container
          .read(collectionsControllerProvider.notifier)
          .create('Temp');
      final folder = (await container.read(
        collectionsControllerProvider.future,
      )).single;
      await container
          .read(libraryControllerProvider.notifier)
          .moveToCollection(1, folder.id);

      await container
          .read(collectionsControllerProvider.notifier)
          .remove(folder.id);

      final docs = await container.read(libraryControllerProvider.future);
      expect(docs, hasLength(1), reason: 'the document must survive');
      expect(docs.single.collectionId, isNull);
    });

    test('deleting the selected folder clears the selection', () async {
      await container.read(collectionsControllerProvider.future);
      await container
          .read(collectionsControllerProvider.notifier)
          .create('Temp');
      final folder = (await container.read(
        collectionsControllerProvider.future,
      )).single;
      container.read(selectedCollectionProvider.notifier).value = folder.id;

      await container
          .read(collectionsControllerProvider.notifier)
          .remove(folder.id);

      expect(container.read(selectedCollectionProvider), isNull);
    });

    test('visibleDocuments filters by the selected folder', () async {
      repo
        ..seed('a.pdf')
        ..seed('b.pdf');
      await container.read(libraryControllerProvider.future);
      await container.read(collectionsControllerProvider.future);
      await container.read(collectionsControllerProvider.notifier).create('F');
      final folder = (await container.read(
        collectionsControllerProvider.future,
      )).single;
      await container
          .read(libraryControllerProvider.notifier)
          .moveToCollection(1, folder.id);

      container.read(selectedCollectionProvider.notifier).value = folder.id;
      expect(container.read(visibleDocumentsProvider).value, hasLength(1));

      container.read(selectedCollectionProvider.notifier).value = null;
      expect(container.read(visibleDocumentsProvider).value, hasLength(2));
    });
  });
}
