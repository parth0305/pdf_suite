import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/models/protect_request.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/protection_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class ProtectionRepositoryImpl implements ProtectionRepository {
  ProtectionRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<LibraryDocument> protect(
    int documentId,
    ProtectRequest request,
  ) async {
    final password = request.userPassword;
    if (password.isEmpty) {
      throw ArgumentError.value(
        // Never the password itself: it must not reach a log or an error.
        '',
        'password',
        'a password is required',
      );
    }

    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    final secured = writePdfDocument(
      bytes,
      parsePdfObjects(bytes),
      encryption: PdfEncryption(
        userPassword: password,
        ownerPassword: request.distinctOwnerPassword,
        permissions: request.permissions.bits,
      ),
    );

    // No metadata is re-attached: PdfMetadata appends an incremental update,
    // which would sit unencrypted after an encrypted document and defeat it.
    return _documents.store(secured, editedName(doc.displayName));
  }
}
