import 'package:folio/domain/compression/compression_estimate.dart';
import 'package:folio/domain/models/library_document.dart';

/// Compresses a document losslessly, into a new document.
abstract interface class CompressionRepository {
  /// Compresses and reports what it saved, WITHOUT storing anything.
  ///
  /// The work is done once: [save] takes the result back, so accepting it
  /// costs nothing further and cannot produce a different file from the one
  /// the user was shown.
  Future<CompressionResult> analyse(int documentId);

  Future<LibraryDocument> save(int documentId, CompressionResult result);
}
