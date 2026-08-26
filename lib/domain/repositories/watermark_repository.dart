import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// Stamps a watermark across every page, into a new document.
abstract interface class WatermarkRepository {
  Future<LibraryDocument> apply(int documentId, Watermark mark);
}
