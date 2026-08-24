import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/file_system/platform_handles.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/models/document_ref.dart';

/// Stands in for the platform channel, which only answers on a real device.
class _StubHandles implements PlatformHandles {
  _StubHandles(this.target);
  final String target;
  var released = false;

  @override
  Future<ExternalHandle> capture(String pathOrUri) async =>
      PathHandle(pathOrUri);

  @override
  Future<String> resolveToReadablePath(ExternalHandle handle) async {
    if (!File(target).existsSync()) {
      throw const DocumentMoved(technicalDetail: 'stub: gone');
    }
    return target;
  }

  @override
  Future<void> release(ExternalHandle handle) async => released = true;
}

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late LibraryRepositoryImpl repo;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('library_repo_test');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<File> sourceFile(String name, List<int> bytes) async {
    final f = File('${sandbox.path}/src_$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('importFile', () {
    test('copies into the library and leaves the original untouched', () async {
      final src = await sourceFile('a.pdf', [37, 80, 68, 70, 1, 2, 3]);

      final doc = await repo.importFile(src.path, displayName: 'a.pdf');

      expect(src.existsSync(), isTrue, reason: 'the original must survive');
      expect(doc.ref, isA<ManagedRef>());
      final copied = File(await repo.resolveReadablePath(doc));
      expect(copied.existsSync(), isTrue);
      expect(await copied.readAsBytes(), await src.readAsBytes());
    });

    test('records the size and a content hash', () async {
      final src = await sourceFile('b.pdf', [37, 80, 68, 70, 9]);
      final doc = await repo.importFile(src.path, displayName: 'b.pdf');

      expect(doc.sizeBytes, 5);
      expect((doc.ref as ManagedRef).contentHash, isNotEmpty);
    });

    test('identical bytes produce the same content hash', () async {
      final a = await sourceFile('c1.pdf', [37, 80, 68, 70, 7]);
      final b = await sourceFile('c2.pdf', [37, 80, 68, 70, 7]);

      final da = await repo.importFile(a.path, displayName: 'c1.pdf');
      final db2 = await repo.importFile(b.path, displayName: 'c2.pdf');

      expect(
        (da.ref as ManagedRef).contentHash,
        (db2.ref as ManagedRef).contentHash,
      );
    });

    test('rejects a file that is not a PDF', () async {
      final src = await sourceFile('not.pdf', [1, 2, 3, 4]);

      await expectLater(
        repo.importFile(src.path, displayName: 'not.pdf'),
        throwsA(isA<DocumentCorrupt>()),
      );
    });

    test('rejects a file too short to contain a header', () async {
      final src = await sourceFile('tiny.pdf', [37]);

      await expectLater(
        repo.importFile(src.path, displayName: 'tiny.pdf'),
        throwsA(isA<DocumentCorrupt>()),
      );
    });

    test('a missing source yields DocumentMoved', () async {
      await expectLater(
        repo.importFile('${sandbox.path}/nope.pdf', displayName: 'nope.pdf'),
        throwsA(isA<DocumentMoved>()),
      );
    });
  });

  group('lifecycle', () {
    test(
      'delete removes the row and the managed copy but never the original',
      () async {
        final src = await sourceFile('d.pdf', [37, 80, 68, 70, 5]);
        final doc = await repo.importFile(src.path, displayName: 'd.pdf');
        final path = await repo.resolveReadablePath(doc);

        await repo.delete(doc.id);

        expect(File(path).existsSync(), isFalse);
        expect(await repo.all(), isEmpty);
        expect(
          src.existsSync(),
          isTrue,
          reason: 'user originals are never deleted',
        );
      },
    );

    test('duplicate creates an independent copy', () async {
      final src = await sourceFile('e.pdf', [37, 80, 68, 70, 6]);
      final original = await repo.importFile(src.path, displayName: 'e.pdf');

      final copy = await repo.duplicate(original.id);

      expect(copy.id, isNot(original.id));
      expect(
        await repo.resolveReadablePath(copy),
        isNot(await repo.resolveReadablePath(original)),
      );
      expect(await repo.all(), hasLength(2));
    });

    test('a managed copy deleted underneath us yields DocumentMoved', () async {
      final src = await sourceFile('f.pdf', [37, 80, 68, 70, 8]);
      final doc = await repo.importFile(src.path, displayName: 'f.pdf');
      await File(await repo.resolveReadablePath(doc)).delete();

      await expectLater(
        repo.resolveReadablePath(doc),
        throwsA(isA<DocumentMoved>()),
      );
    });
  });

  group('openInPlace', () {
    test('records an ExternalRef and does not copy the file', () async {
      final src = await sourceFile('ext.pdf', [37, 80, 68, 70, 4]);
      final repoExt = LibraryRepositoryImpl(
        dao: LibraryDao(db),
        writer: SafeFileWriter(),
        libraryRoot: sandbox,
        handles: _StubHandles(src.path),
      );

      final doc = await repoExt.openInPlace(src.path, displayName: 'ext.pdf');

      expect(doc.ref, isA<ExternalRef>());
      expect(doc.isManaged, isFalse);
      expect(doc.sizeBytes, 5);
      expect(await repoExt.resolveReadablePath(doc), src.path);
    });

    test('deleting an external document never touches the user file', () async {
      final src = await sourceFile('ext2.pdf', [37, 80, 68, 70, 4]);
      final repoExt = LibraryRepositoryImpl(
        dao: LibraryDao(db),
        writer: SafeFileWriter(),
        libraryRoot: sandbox,
        handles: _StubHandles(src.path),
      );
      final doc = await repoExt.openInPlace(src.path, displayName: 'ext2.pdf');

      await repoExt.delete(doc.id);

      expect(
        src.existsSync(),
        isTrue,
        reason: 'we never own an external file, so we never delete it',
      );
      expect(await repoExt.all(), isEmpty);
    });

    test('an external file that disappears yields DocumentMoved', () async {
      final src = await sourceFile('ext3.pdf', [37, 80, 68, 70, 4]);
      final repoExt = LibraryRepositoryImpl(
        dao: LibraryDao(db),
        writer: SafeFileWriter(),
        libraryRoot: sandbox,
        handles: _StubHandles(src.path),
      );
      final doc = await repoExt.openInPlace(src.path, displayName: 'ext3.pdf');
      await src.delete();

      await expectLater(
        repoExt.resolveReadablePath(doc),
        throwsA(isA<DocumentMoved>()),
      );
    });
  });

  group('mutations', () {
    test('markOpened, setFavorite and rename round-trip', () async {
      final src = await sourceFile('m.pdf', [37, 80, 68, 70, 1]);
      final doc = await repo.importFile(src.path, displayName: 'm.pdf');

      await repo.markOpened(doc.id);
      await repo.setFavorite(doc.id, true);
      await repo.rename(doc.id, 'renamed.pdf');

      final updated = (await repo.all()).single;
      expect(updated.lastOpenedAt, isNotNull);
      expect(updated.isFavorite, isTrue);
      expect(updated.displayName, 'renamed.pdf');
      expect(await repo.recents(), hasLength(1));
      expect(await repo.favorites(), hasLength(1));
    });
  });

  group('exportCopy', () {
    test(
      'writes a copy to the destination and leaves the library intact',
      () async {
        final src = await sourceFile('x.pdf', [37, 80, 68, 70, 1, 2, 3]);
        final doc = await repo.importFile(src.path, displayName: 'x.pdf');
        final dest = File('${sandbox.path}/exported.pdf');

        await repo.exportCopy(doc.id, dest.path);

        expect(dest.existsSync(), isTrue);
        expect(await dest.readAsBytes(), await src.readAsBytes());
        expect(
          File(await repo.resolveReadablePath(doc)).existsSync(),
          isTrue,
          reason: 'Save As exports; it must not move the library copy',
        );
      },
    );

    test('exporting a missing managed copy yields DocumentMoved', () async {
      final src = await sourceFile('y.pdf', [37, 80, 68, 70, 2]);
      final doc = await repo.importFile(src.path, displayName: 'y.pdf');
      await File(await repo.resolveReadablePath(doc)).delete();

      await expectLater(
        repo.exportCopy(doc.id, '${sandbox.path}/out.pdf'),
        throwsA(isA<DocumentMoved>()),
      );
    });
  });

  group('moveToCollection', () {
    test('moves a document into a collection and back to the root', () async {
      final src = await sourceFile('z.pdf', [37, 80, 68, 70, 3]);
      final doc = await repo.importFile(src.path, displayName: 'z.pdf');
      final dao = LibraryDao(db);
      final folder = await dao.createCollection('Invoices');

      await repo.moveToCollection(doc.id, folder);
      expect(await dao.documentsIn(folder), hasLength(1));

      await repo.moveToCollection(doc.id, null);
      expect(await dao.documentsIn(null), hasLength(1));
    });

    test('moving never touches the file on disk', () async {
      final src = await sourceFile('w.pdf', [37, 80, 68, 70, 4]);
      final doc = await repo.importFile(src.path, displayName: 'w.pdf');
      final before = await repo.resolveReadablePath(doc);
      final dao = LibraryDao(db);
      final folder = await dao.createCollection('Reports');

      await repo.moveToCollection(doc.id, folder);

      expect(
        await repo.resolveReadablePath(doc),
        before,
        reason:
            'folders are virtual; a move is an UPDATE, not a file operation',
      );
      expect(File(before).existsSync(), isTrue);
    });
  });
}
