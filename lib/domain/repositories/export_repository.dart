import 'package:folio/domain/sharing/document_export.dart';

/// Why a document could not be printed.
enum PrintRefusal { protected }

/// Prepares documents to leave the device, and hands them over.
///
/// The two are separate on purpose: preparing is testable without a platform,
/// and handing over is the part that only exists on a real device.
abstract interface class ExportRepository {
  /// Reads a document and works out whether it can be printed.
  Future<DocumentExport> prepare(int documentId);

  /// Null when [export] can be printed.
  PrintRefusal? refusalFor(DocumentExport export);
}
