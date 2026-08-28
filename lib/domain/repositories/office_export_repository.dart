import 'package:folio/domain/models/library_document.dart';

/// The Office formats Folio writes.
enum OfficeFormat {
  word('docx'),
  excel('xlsx'),
  powerPoint('pptx');

  const OfficeFormat(this.extension);

  final String extension;
}

/// A converted document on its way out.
class ExportedOfficeFile {
  const ExportedOfficeFile({required this.path, required this.name});

  final String path;
  final String name;
}

/// Converts a PDF's text into an Office document.
abstract interface class OfficeExportRepository {
  Future<ExportedOfficeFile> export(int documentId, OfficeFormat format);

  /// Whether there is any text to convert.
  ///
  /// A scan has none until it has been through OCR, and a Word document with
  /// nothing in it is a worse answer than saying so first.
  Future<bool> hasText(int documentId);
}

/// The name a converted file takes.
String officeName(LibraryDocument document, OfficeFormat format) {
  final dot = document.displayName.lastIndexOf('.');
  final stem = dot <= 0
      ? document.displayName
      : document.displayName.substring(0, dot);

  return '$stem.${format.extension}';
}
