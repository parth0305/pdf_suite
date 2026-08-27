import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// Stamps a watermark across every page, into a new document.
abstract interface class WatermarkRepository {
  /// Stamps an image across every page, into a new document.
  Future<LibraryDocument> applyImage(int documentId, ImageWatermark mark);

  /// Removes a watermark **Folio applied**, into a new document.
  ///
  /// Throws `UnsupportedPdfStructure` when the document carries no watermark
  /// Folio can identify. A mark applied by another tool leaves no reliable
  /// marker, and guessing which parts of a content stream belong to it is the
  /// same problem as redaction.
  Future<LibraryDocument> remove(int documentId);

  Future<LibraryDocument> apply(int documentId, Watermark mark);
}
