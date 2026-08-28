import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/forms/form_field.dart';
import 'package:folio/domain/forms/pdf_form_reader.dart';
import 'package:folio/domain/forms/pdf_form_writer.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/form_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class FormRepositoryImpl implements FormRepository {
  FormRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<List<FormField>> fields(int documentId) async => PdfFormReader.parse(
    latin1.decode(await _bytesOf(documentId), allowInvalid: true),
  ).fields;

  @override
  Future<LibraryDocument> fill(
    int documentId,
    Map<String, String?> values,
  ) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await _bytesOf(documentId);

    return _documents.store(
      writeFilledForm(bytes, values),
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }

  Future<Uint8List> _bytesOf(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    return File(await _library.resolveReadablePath(doc)).readAsBytes();
  }
}
