/// One exported page, written to a temporary file ready to be handed out.
class ExportedPage {
  const ExportedPage({required this.path, required this.pageNumber});

  final String path;
  final int pageNumber;
}

/// Renders pages as images.
abstract interface class ImageExportRepository {
  /// Exports the pages in [range] at [dpi], as PNG files.
  ///
  /// PNG rather than JPEG, and deliberately: `dart:ui` encodes PNG only, and
  /// for a page of text PNG is both smaller and sharper — a 300 DPI A4 page
  /// measured 100 KB, where JPEG would smear the glyph edges to no benefit.
  Future<List<ExportedPage>> export({
    required int documentId,
    required String range,
    required int dpi,
  });
}
