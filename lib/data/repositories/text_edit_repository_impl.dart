import 'dart:io';
import 'dart:typed_data';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/editing/pdf_text_editor.dart';
import 'package:folio/domain/editing/text_edit.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/text_edit_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class TextEditRepositoryImpl implements TextEditRepository {
  TextEditRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<List<EditableRun>> runsOn(int documentId, int pageIndex) async =>
      PdfTextEditor.parse(await _bytesOf(documentId)).runsOn(pageIndex);

  @override
  Future<EditPlan> plan(
    int documentId,
    EditableRun run,
    String replacement,
  ) async =>
      PdfTextEditor.parse(await _bytesOf(documentId)).plan(run, replacement);

  @override
  Future<LibraryDocument> apply(
    int documentId,
    EditableRun run,
    String replacement,
  ) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await _bytesOf(documentId);

    return _documents.store(
      PdfTextEditor.parse(bytes).apply(run, replacement),
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }

  Future<Uint8List> _bytesOf(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    return File(await _library.resolveReadablePath(doc)).readAsBytes();
  }
}
