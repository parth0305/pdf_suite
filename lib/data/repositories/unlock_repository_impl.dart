import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/pdf/pdf_unlock.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/unlock_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class UnlockRepositoryImpl implements UnlockRepository {
  UnlockRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<LibraryDocument> unlock(int documentId, String password) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    // Throws before anything is written: a wrong password must not leave a
    // half-made document behind.
    final unlocked = unlockPdf(bytes, password);

    // No metadata is re-attached. It is already inside the unlocked bytes,
    // decrypted; appending an incremental update would add a second /Info.
    return _documents.store(unlocked, editedName(doc.displayName));
  }
}
