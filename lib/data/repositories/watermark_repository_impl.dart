import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/watermark_repository.dart';
import 'package:folio/domain/services/edited_name.dart';
import 'package:folio/domain/watermark/pdf_watermark_writer.dart';
import 'package:folio/domain/watermark/watermark.dart';

class WatermarkRepositoryImpl implements WatermarkRepository {
  WatermarkRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<LibraryDocument> apply(int documentId, Watermark mark) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    // Throws ArgumentError on empty text before anything is written.
    final marked = writeWatermark(bytes, mark);

    // Metadata is re-read from the source so the new document inherits it,
    // exactly as every other write path does.
    return _documents.store(
      marked,
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }
}
