import 'package:folio/domain/batch/batch_outcome.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// Applies one operation to many documents.
abstract interface class BatchRepository {
  /// Runs [action] over [documentIds], reporting progress as it goes.
  ///
  /// Runs to completion: a document that fails is recorded and the batch
  /// continues. [onProgress] is called with how many are finished, so a slow
  /// batch - OCR takes seconds per page - can show real progress.
  ///
  /// [shouldContinue] is checked before each document. Returning false stops
  /// the batch, and everything already produced STAYS: a cancel that undid
  /// completed work would be a rollback nobody asked for.
  Future<BatchOutcome> run({
    required BatchAction action,
    required List<int> documentIds,
    Watermark? watermark,
    String? password,
    void Function(int done, int total)? onProgress,
    bool Function()? shouldContinue,
  });
}
