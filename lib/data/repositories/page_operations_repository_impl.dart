import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/editing/pdf_page_editor.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/page_operations_repository.dart';
import 'package:folio/domain/services/edited_name.dart';
import 'package:path/path.dart' as p;

typedef OpenSource = Future<PdfDocumentHandle> Function(LibraryDocument doc);
typedef CloseSource = Future<void> Function(PdfDocumentHandle handle);

class PageOperationsRepositoryImpl implements PageOperationsRepository {
  PageOperationsRepositoryImpl({
    required LibraryRepository library,
    required SafeFileWriter writer,
    required Directory libraryRoot,
    required PdfPageEditor editor,
    required OpenSource openSource,
    required CloseSource closeSource,
  }) : _library = library,
       _writer = writer,
       _root = libraryRoot,
       _editor = editor,
       _open = openSource,
       _close = closeSource;

  final LibraryRepository _library;
  final SafeFileWriter _writer;
  final Directory _root;
  final PdfPageEditor _editor;
  final OpenSource _open;
  final CloseSource _close;

  Future<LibraryDocument> _documentById(int id) async =>
      (await _library.all()).firstWhere((d) => d.id == id);

  /// Every distinct document the slots draw from.
  ///
  /// Slots may reference more than the document being edited: inserting pages
  /// from another document leaves its id in the list, and materialising then
  /// needs a handle for it too.
  Future<List<LibraryDocument>> _sourcesFor(List<PageSlot> slots) async {
    final ids = {for (final slot in slots) slot.sourceDocumentId};
    final all = await _library.all();
    return [for (final id in ids) all.firstWhere((d) => d.id == id)];
  }

  /// Opens the needed sources, materialises, then always closes them, so a
  /// failure part-way cannot leak native handles.
  Future<Uint8List> _materialise(
    List<PageSlot> slots,
    List<LibraryDocument> sources,
  ) async {
    final handles = <int, PdfDocumentHandle>{};
    try {
      for (final doc in sources) {
        handles[doc.id] = await _open(doc);
      }
      return await _editor.materialise(slots: slots, sources: handles);
    } finally {
      for (final handle in handles.values) {
        await _close(handle);
      }
    }
  }

  /// Reads the metadata a produced document should carry.
  ///
  /// The writer discards the source's /Info, so it is read from the original
  /// bytes and re-attached in [_store]. On merge the first document wins,
  /// matching how the merged output is already named after it.
  Future<PdfMetadata?> _metadataOf(LibraryDocument source) async {
    try {
      final path = await _library.resolveReadablePath(source);
      return PdfMetadata.readFrom(await File(path).readAsBytes());
    } catch (_) {
      // Metadata is a nicety; failing to read it must never fail the operation.
      return null;
    }
  }

  /// Writes bytes into the library as a new content-addressed document.
  ///
  /// [metadata], when present, is re-attached first: the writer drops the
  /// source's /Info, so without this every page operation would silently
  /// discard the document's title, author and subject.
  Future<LibraryDocument> _store(
    Uint8List bytes,
    String displayName, {
    PdfMetadata? metadata,
  }) async {
    if (metadata != null && !metadata.isEmpty) {
      try {
        bytes = metadata.appendTo(bytes);
      } on FormatException {
        // Preserving metadata is best-effort. A document we cannot patch is
        // still a valid document; losing its title is better than losing it.
      }
    }
    final hash = sha256.convert(bytes).toString();
    final relative = p.join(hash.substring(0, 2), '$hash.pdf');

    await _writer.write(
      destination: File(p.join(_root.path, relative)),
      produce: (working) => working.writeAsBytes(bytes, flush: true),
      validate: (working) async => await working.length() == bytes.length,
    );

    return _library.registerManaged(
      relativePath: relative,
      contentHash: hash,
      displayName: displayName,
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<LibraryDocument> apply({
    required int sourceDocumentId,
    required List<PageSlot> slots,
  }) async {
    final source = await _documentById(sourceDocumentId);
    final metadata = await _metadataOf(source);
    final bytes = await _materialise(slots, await _sourcesFor(slots));
    return _store(bytes, editedName(source.displayName), metadata: metadata);
  }

  @override
  Future<LibraryDocument> merge({required List<int> documentIds}) async {
    if (documentIds.length < 2) {
      throw ArgumentError.value(
        documentIds,
        'documentIds',
        'merging needs at least two documents',
      );
    }

    final sources = <LibraryDocument>[];
    for (final id in documentIds) {
      sources.add(await _documentById(id));
    }

    final handles = <int, PdfDocumentHandle>{};
    final slots = <PageSlot>[];
    try {
      for (final doc in sources) {
        final handle = await _open(doc);
        handles[doc.id] = handle;
        for (var i = 0; i < handle.pageCount; i++) {
          slots.add(PageSlot(sourceDocumentId: doc.id, sourcePageIndex: i));
        }
      }
      final bytes = await _editor.materialise(slots: slots, sources: handles);
      return await _store(
        bytes,
        editedName(sources.first.displayName),
        metadata: await _metadataOf(sources.first),
      );
    } finally {
      for (final handle in handles.values) {
        await _close(handle);
      }
    }
  }

  @override
  Future<LibraryDocument> extractPages({
    required int sourceDocumentId,
    required List<PageSlot> slots,
  }) async {
    final source = await _documentById(sourceDocumentId);
    final metadata = await _metadataOf(source);
    final bytes = await _materialise(slots, await _sourcesFor(slots));
    return _store(
      bytes,
      extractedName(source.displayName, slots.length),
      metadata: metadata,
    );
  }

  @override
  Future<List<LibraryDocument>> split({
    required int sourceDocumentId,
    required List<List<int>> groups,
  }) async {
    if (groups.isEmpty) {
      throw ArgumentError.value(
        groups,
        'groups',
        'split needs at least one group',
      );
    }

    final source = await _documentById(sourceDocumentId);
    final metadata = await _metadataOf(source);
    final created = <LibraryDocument>[];

    try {
      for (var part = 0; part < groups.length; part++) {
        final slots = [
          for (final index in groups[part])
            PageSlot(sourceDocumentId: source.id, sourcePageIndex: index),
        ];
        final bytes = await _materialise(slots, [source]);
        created.add(
          await _store(
            bytes,
            splitPartName(source.displayName, part + 1),
            metadata: metadata,
          ),
        );
      }
      return created;
    } catch (_) {
      // A partial split would litter the library with a half-finished set, so
      // remove what was already written before rethrowing.
      for (final doc in created) {
        await _library.delete(doc.id);
      }
      rethrow;
    }
  }
}
