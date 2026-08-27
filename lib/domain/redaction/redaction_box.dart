import 'package:folio/domain/engine/pdf_types.dart';

/// A region the user asked to have removed, in PDF points on one page.
///
/// PDF points, not screen pixels: a box has to survive zooming, rotation and
/// rasterising at whatever resolution, and the page's own coordinate space is
/// the only one that does.
class RedactionBox {
  const RedactionBox({required this.pageIndex, required this.rect});

  final int pageIndex;
  final TextRect rect;
}
