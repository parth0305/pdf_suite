import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/scanner/scanned_page.dart';

/// Turns captured pages into a new document in the library.
abstract interface class ScannerRepository {
  Future<LibraryDocument> save(List<ScannedPage> pages, {String? name});
}
