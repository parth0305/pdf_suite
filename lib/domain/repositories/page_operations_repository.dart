import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/models/library_document.dart';

/// Page operations that produce new library documents.
///
/// Every method creates new entries. None modifies its source, which is what
/// makes these operations safe to offer without a confirmation dialog.
abstract interface class PageOperationsRepository {
  Future<LibraryDocument> apply({
    required int sourceDocumentId,
    required List<PageSlot> slots,
  });

  Future<LibraryDocument> merge({required List<int> documentIds});

  Future<LibraryDocument> extractPages({
    required int sourceDocumentId,
    required List<PageSlot> slots,
  });

  /// [groups] holds zero-based page indices, one list per output document.
  Future<List<LibraryDocument>> split({
    required int sourceDocumentId,
    required List<List<int>> groups,
  });
}
