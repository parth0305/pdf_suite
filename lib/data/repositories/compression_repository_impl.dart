import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/compression/compression_estimate.dart';
import 'package:folio/domain/compression/pdf_compressor.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/compression_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class CompressionRepositoryImpl implements CompressionRepository {
  CompressionRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<CompressionResult> analyse(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    return compressPdf(bytes);
  }

  @override
  Future<LibraryDocument> save(int documentId, CompressionResult result) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);

    // Metadata is carried across as every other write path does. It costs a
    // few dozen bytes, and losing a document's title to save them would be a
    // poor trade.
    return _documents.store(
      result.bytes,
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(result.bytes),
    );
  }
}
