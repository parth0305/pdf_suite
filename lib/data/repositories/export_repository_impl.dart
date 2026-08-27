import 'dart:convert';
import 'dart:io';

import 'package:folio/domain/repositories/export_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/sharing/document_export.dart';

class ExportRepositoryImpl implements ExportRepository {
  ExportRepositoryImpl({required LibraryRepository library})
    : _library = library;

  final LibraryRepository _library;

  @override
  Future<DocumentExport> prepare(int documentId) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    return DocumentExport(
      bytes: bytes,
      displayName: doc.displayName,
      isProtected: looksEncrypted(latin1.decode(bytes, allowInvalid: true)),
    );
  }

  @override
  PrintRefusal? refusalFor(DocumentExport export) {
    // The operating system's print renderer needs the password, which Folio
    // does not hold and could not hand over safely. Refusing here is clearer
    // than a print job that fails somewhere the user cannot see why.
    if (export.isProtected) return PrintRefusal.protected;
    return null;
  }
}
