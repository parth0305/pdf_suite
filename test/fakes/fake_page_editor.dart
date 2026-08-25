import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/editing/pdf_page_editor.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// In-memory [PdfPageEditor] for unit tests.
///
/// Enforces the same preconditions as the real implementation so callers can
/// be tested against them without a device.
class FakePageEditor implements PdfPageEditor {
  final List<List<PageSlot>> calls = [];

  @override
  Future<Uint8List> materialise({
    required List<PageSlot> slots,
    required Map<int, PdfDocumentHandle> sources,
  }) async {
    if (slots.isEmpty) {
      throw const EmptyDocument(technicalDetail: 'fake: no slots');
    }
    for (final slot in slots) {
      if (!sources.containsKey(slot.sourceDocumentId)) {
        throw ArgumentError.value(
          slot.sourceDocumentId,
          'sources',
          'no handle supplied for this source document',
        );
      }
    }

    calls.add(List.of(slots));
    // %PDF header so callers that sniff the magic bytes behave realistically.
    return Uint8List.fromList([0x25, 0x50, 0x44, 0x46, slots.length]);
  }
}
