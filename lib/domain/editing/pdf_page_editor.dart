import 'dart:typed_data';

import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// The only write path in the application.
///
/// Deliberately separate from `PdfEngine`, which stays read-only so SP-1's
/// compile-time guarantee that the reader cannot alter a PDF survives. Do not
/// merge these two interfaces.
abstract interface class PdfPageEditor {
  /// Materialises [slots] into PDF bytes.
  ///
  /// [sources] maps a source document id to an already-open handle. Every
  /// slot's `sourceDocumentId` must be present, or [ArgumentError] is thrown.
  ///
  /// Throws `EmptyDocument` when [slots] is empty: a PDF with no pages is not
  /// a valid document, and writing one would produce a file that fails to
  /// reopen.
  Future<Uint8List> materialise({
    required List<PageSlot> slots,
    required Map<int, PdfDocumentHandle> sources,
  });
}
