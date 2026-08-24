import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/file_system/platform_handles.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:path/path.dart' as p;

class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl({
    required LibraryDao dao,
    required SafeFileWriter writer,
    required Directory libraryRoot,
    PlatformHandles handles = const PlatformHandles(),
  }) : _dao = dao,
       _writer = writer,
       _root = libraryRoot,
       _handles = handles;

  final LibraryDao _dao;
  final SafeFileWriter _writer;
  final Directory _root;
  final PlatformHandles _handles;

  /// `%PDF` - checked before import so obviously wrong files are rejected at
  /// the door rather than failing later inside the engine.
  static const List<int> _pdfMagic = [0x25, 0x50, 0x44, 0x46];

  @override
  Future<LibraryDocument> importFile(
    String sourcePath, {
    required String displayName,
  }) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const DocumentMoved(technicalDetail: 'source file does not exist');
    }

    final bytes = await source.readAsBytes();
    if (bytes.length < _pdfMagic.length || !_startsWithPdfMagic(bytes)) {
      throw const DocumentCorrupt(technicalDetail: 'missing %PDF header');
    }

    final hash = sha256.convert(bytes).toString();
    final relative = p.join(hash.substring(0, 2), '$hash.pdf');
    final destination = File(p.join(_root.path, relative));

    await _writer.write(
      destination: destination,
      produce: (working) => working.writeAsBytes(bytes, flush: true),
      validate: (working) async => await working.length() == bytes.length,
    );

    final id = await _dao.insertDocument(
      ref: ManagedRef(relativePath: relative, contentHash: hash),
      displayName: displayName,
      sizeBytes: bytes.length,
    );

    return (await all()).firstWhere((d) => d.id == id);
  }

  bool _startsWithPdfMagic(List<int> bytes) {
    for (var i = 0; i < _pdfMagic.length; i++) {
      if (bytes[i] != _pdfMagic[i]) return false;
    }
    return true;
  }

  @override
  Future<LibraryDocument> openInPlace(
    String pathOrUri, {
    required String displayName,
  }) async {
    final handle = await _handles.capture(pathOrUri);
    final resolved = await _handles.resolveToReadablePath(handle);
    final size = await File(resolved).length();

    final id = await _dao.insertDocument(
      ref: ExternalRef(handle: handle, displayName: displayName),
      displayName: displayName,
      sizeBytes: size,
    );
    return (await all()).firstWhere((d) => d.id == id);
  }

  @override
  Future<String> resolveReadablePath(LibraryDocument doc) async {
    return switch (doc.ref) {
      ManagedRef(:final relativePath) => _requireManaged(relativePath),
      ExternalRef(:final handle) => await _handles.resolveToReadablePath(
        handle,
      ),
    };
  }

  String _requireManaged(String relativePath) {
    final file = File(p.join(_root.path, relativePath));
    if (!file.existsSync()) {
      throw const DocumentMoved(technicalDetail: 'managed copy is missing');
    }
    return file.path;
  }

  @override
  Future<List<LibraryDocument>> all() => _dao.allDocuments();

  @override
  Future<List<LibraryDocument>> recents({int limit = 20}) =>
      _dao.recents(limit: limit);

  @override
  Future<List<LibraryDocument>> favorites() => _dao.favorites();

  @override
  Future<void> markOpened(int id) => _dao.markOpened(id);

  @override
  Future<void> setFavorite(int id, bool value) => _dao.setFavorite(id, value);

  @override
  Future<void> rename(int id, String name) => _dao.rename(id, name);

  @override
  Future<void> delete(int id) async {
    final doc = (await all()).firstWhere((d) => d.id == id);
    // Only ever delete a copy the app made. A user's own file is never removed.
    if (doc.ref case ManagedRef(:final relativePath)) {
      final file = File(p.join(_root.path, relativePath));
      if (file.existsSync()) await file.delete();
    }
    await _dao.deleteDocument(id);
  }

  @override
  Future<LibraryDocument> duplicate(int id) async {
    final doc = (await all()).firstWhere((d) => d.id == id);
    final bytes = await File(await resolveReadablePath(doc)).readAsBytes();

    // Salt the hash so the duplicate becomes a distinct managed file rather
    // than collapsing onto the original's content-addressed path.
    final salted = sha256.convert([
      ...bytes,
      ...DateTime.now().toIso8601String().codeUnits,
    ]).toString();
    final relative = p.join(salted.substring(0, 2), '$salted.pdf');

    await _writer.write(
      destination: File(p.join(_root.path, relative)),
      produce: (working) => working.writeAsBytes(bytes, flush: true),
    );

    final newId = await _dao.insertDocument(
      ref: ManagedRef(relativePath: relative, contentHash: salted),
      displayName: '${doc.displayName} copy',
      sizeBytes: bytes.length,
    );
    return (await all()).firstWhere((d) => d.id == newId);
  }
}
