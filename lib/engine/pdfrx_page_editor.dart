import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/editing/pdf_page_editor.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

/// [PdfPageEditor] backed by pdfrx / PDFium.
///
/// Builds a fresh document and assigns it pages drawn from the source
/// documents, which is the write path SP-1's spike verified round-trips with
/// order and rotation intact.
class PdfrxPageEditor implements PdfPageEditor {
  PdfrxPageEditor(this._engine);

  final PdfrxEngine _engine;

  static const List<rx.PdfPageRotation> _rotations = [
    rx.PdfPageRotation.none,
    rx.PdfPageRotation.clockwise90,
    rx.PdfPageRotation.clockwise180,
    rx.PdfPageRotation.clockwise270,
  ];

  @override
  Future<Uint8List> materialise({
    required List<PageSlot> slots,
    required Map<int, PdfDocumentHandle> sources,
  }) async {
    if (slots.isEmpty) {
      throw const EmptyDocument(technicalDetail: 'no pages to write');
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

    try {
      final output = await rx.PdfDocument.createNew(sourceName: 'edited.pdf');

      output.pages = [
        for (final slot in slots)
          _pageFor(slot, sources[slot.sourceDocumentId]!),
      ];

      // Required before encoding: it makes the new document independent of the
      // sources, which must stay open until this returns.
      await output.assemble();
      final bytes = await output.encodePdf();
      await output.dispose();
      return bytes;
    } on rx.PdfException catch (e) {
      throw DocumentCorrupt(technicalDetail: e.toString());
    } on ArgumentError {
      rethrow;
    } catch (e) {
      throw UnknownFailure(technicalDetail: e.toString());
    }
  }

  rx.PdfPage _pageFor(PageSlot slot, PdfDocumentHandle handle) {
    final page = _engine.documentFor(handle).pages[slot.sourcePageIndex];
    if (slot.quarterTurns == 0) return page;

    // rotatedTo is absolute, so compose the page's existing rotation with the
    // slot's accumulated turns rather than replacing it.
    final combined = (page.rotation.index + slot.quarterTurns) % 4;
    return page.rotatedTo(_rotations[combined]);
  }
}
