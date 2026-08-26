import 'dart:typed_data';

/// Opaque handle to an open document. Only the engine that produced it may use it.
class PdfDocumentHandle {
  const PdfDocumentHandle({
    required this.id,
    required this.pageCount,
    this.permissionBits,
  });

  final String id;
  final int pageCount;

  /// The raw /P bit field, or null when the document is not protected.
  ///
  /// Kept as the integer the reader parsed rather than a set of booleans:
  /// engines disagree about which bit means what, and the value is only ever
  /// compared against what Folio wrote.
  final int? permissionBits;
}

class PdfPageInfo {
  const PdfPageInfo({
    required this.index,
    required this.widthPt,
    required this.heightPt,
    required this.rotationQuarterTurns,
  });

  final int index;
  final double widthPt;
  final double heightPt;
  final int rotationQuarterTurns;

  bool get isLandscape => widthPt > heightPt;
}

/// A rasterized page. [bgraPixels] is BGRA8888, matching PDFium's output.
class RenderedPage {
  const RenderedPage({
    required this.widthPx,
    required this.heightPx,
    required this.bgraPixels,
  });

  final int widthPx;
  final int heightPx;
  final Uint8List bgraPixels;
}

/// A rectangle in PDF user space. **The origin is bottom-left and y increases
/// upward**, so [top] is numerically greater than [bottom]. Converting to
/// Flutter's y-down screen space requires flipping against the page height.
class TextRect {
  const TextRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => top - bottom;
}

/// Extracted page text. [charRects] has exactly one entry per code unit in
/// [fullText], so `charRects[i]` locates `fullText[i]`. Search highlighting and
/// selection both rely on this alignment.
class PageText {
  const PageText({required this.fullText, required this.charRects});
  final String fullText;
  final List<TextRect> charRects;

  bool get isEmpty => fullText.isEmpty;
}

class OutlineNode {
  const OutlineNode({
    required this.title,
    required this.pageIndex,
    required this.children,
  });

  final String title;
  final int? pageIndex;
  final List<OutlineNode> children;
}

class DocumentPermissions {
  const DocumentPermissions({
    required this.allowsCopying,
    required this.allowsPrinting,
    required this.allowsDocumentAssembly,
    required this.allowsModifyAnnotations,
    required this.securityHandlerRevision,
  });

  final bool allowsCopying;
  final bool allowsPrinting;
  final bool allowsDocumentAssembly;
  final bool allowsModifyAnnotations;
  final int securityHandlerRevision;
}
