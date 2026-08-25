import 'package:folio/domain/engine/pdf_types.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

/// Converts a pdfrx outline node to the domain type.
///
/// Shared by [PdfrxEngine] and the viewer's outline panel so the 1-based to
/// 0-based page conversion exists in exactly one place.
OutlineNode convertOutlineNode(rx.PdfOutlineNode node) => OutlineNode(
  title: node.title,
  // PdfDest.pageNumber is 1-based; the domain API is 0-based.
  pageIndex: node.dest?.pageNumber == null ? null : node.dest!.pageNumber - 1,
  children: node.children.map(convertOutlineNode).toList(),
);
