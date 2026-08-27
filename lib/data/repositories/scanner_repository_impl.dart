import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/scanner_repository.dart';
import 'package:folio/domain/scanner/pdf_image_document.dart';
import 'package:folio/domain/scanner/scanned_page.dart';

class ScannerRepositoryImpl implements ScannerRepository {
  ScannerRepositoryImpl({required DocumentWriter documents})
    : _documents = documents;

  final DocumentWriter _documents;

  @override
  Future<LibraryDocument> save(List<ScannedPage> pages, {String? name}) async {
    // Throws ArgumentError on an empty list before anything is written.
    final bytes = buildScannedDocument(pages);

    // No metadata is attached. A scan has no source document to inherit a
    // title or author from, and inventing one would put Folio's name in a
    // file that is meant to be the user's.
    return _documents.store(bytes, name ?? scannedName(DateTime.now()));
  }
}

/// Names a scan by when it was taken, since there is no source document to
/// take a name from.
String scannedName(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');

  return 'Scan ${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}${two(at.minute)}${two(at.second)}.pdf';
}
