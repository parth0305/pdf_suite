import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/archive/pdfa_check.dart';
import 'package:folio/domain/archive/pdfa_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/archive_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class ArchiveRepositoryImpl implements ArchiveRepository {
  ArchiveRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<PdfaReport> check(int documentId) async =>
      checkPdfa(latin1.decode(await _bytesOf(documentId), allowInvalid: true));

  @override
  Future<LibraryDocument> convert(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await _bytesOf(documentId);

    return _documents.store(
      writePdfaDocument(bytes),
      archivedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }

  Future<Uint8List> _bytesOf(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    return File(await _library.resolveReadablePath(doc)).readAsBytes();
  }
}
