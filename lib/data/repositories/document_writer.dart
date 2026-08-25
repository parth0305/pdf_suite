import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:path/path.dart' as p;

/// The single place a produced document enters the library.
///
/// Every writer - page operations, annotations, anything later - goes through
/// here, so metadata preservation cannot be forgotten by a new caller. That
/// exact omission was the SP-2b data-loss bug.
class DocumentWriter {
  const DocumentWriter({
    required LibraryRepository library,
    required SafeFileWriter writer,
    required Directory libraryRoot,
  }) : _library = library,
       _writer = writer,
       _root = libraryRoot;

  final LibraryRepository _library;
  final SafeFileWriter _writer;
  final Directory _root;

  /// Writes [bytes] into the library as a new content-addressed document,
  /// re-attaching [metadata] first when supplied.
  ///
  /// Metadata re-attachment is best-effort: a document that cannot be patched
  /// is still written, because losing a title is better than losing the file.
  Future<LibraryDocument> store(
    Uint8List bytes,
    String displayName, {
    PdfMetadata? metadata,
  }) async {
    var payload = bytes;
    if (metadata != null && !metadata.isEmpty) {
      try {
        payload = metadata.appendTo(payload);
      } on FormatException {
        // Not a classic-xref document; keep the unpatched bytes.
      }
    }

    final hash = sha256.convert(payload).toString();
    final relative = p.join(hash.substring(0, 2), '$hash.pdf');

    await _writer.write(
      destination: File(p.join(_root.path, relative)),
      produce: (working) => working.writeAsBytes(payload, flush: true),
      validate: (working) async => await working.length() == payload.length,
    );

    return _library.registerManaged(
      relativePath: relative,
      contentHash: hash,
      displayName: displayName,
      sizeBytes: payload.length,
    );
  }
}
