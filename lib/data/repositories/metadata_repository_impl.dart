import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/metadata_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class MetadataRepositoryImpl implements MetadataRepository {
  MetadataRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<PdfMetadata> read(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    return PdfMetadata.readFrom(bytes) ?? const PdfMetadata();
  }

  @override
  Future<LibraryDocument> save(int documentId, PdfMetadata metadata) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    if (metadata.isEmpty) {
      throw ArgumentError.value(metadata, 'metadata', 'nothing to write');
    }

    // appendTo writes an incremental update, which is right: nothing is being
    // removed, and the newest /Info wins for any reader walking the trailer
    // chain backwards.
    return _documents.store(
      metadata.appendTo(bytes),
      editedName(doc.displayName),
    );
  }
}
