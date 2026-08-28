import 'package:folio/domain/crop/page_crop.dart';
import 'package:folio/domain/models/library_document.dart';

/// Trims page margins, into a new document.
abstract interface class CropRepository {
  /// The margins that would trim every page to its content, in points.
  ///
  /// Safe on the whole document: where pages disagree, the smallest margin
  /// wins, so no page loses content to another page's wider white space.
  Future<PageMargins> detect(int documentId);

  Future<LibraryDocument> apply(int documentId, PageMargins margins);
}
