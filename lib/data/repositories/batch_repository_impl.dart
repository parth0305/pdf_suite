import 'package:folio/domain/batch/batch_outcome.dart';
import 'package:folio/domain/models/protect_request.dart';
import 'package:folio/domain/repositories/batch_repository.dart';
import 'package:folio/domain/repositories/compression_repository.dart';
import 'package:folio/domain/repositories/ocr_repository.dart';
import 'package:folio/domain/repositories/protection_repository.dart';
import 'package:folio/domain/repositories/watermark_repository.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// Runs an existing single-document operation over many documents.
///
/// It owns no PDF logic of its own. Every action delegates to the repository
/// that already does that job alone, so a batch cannot drift from what the
/// single-document path does.
class BatchRepositoryImpl implements BatchRepository {
  BatchRepositoryImpl({
    required CompressionRepository compression,
    required OcrRepository ocr,
    required WatermarkRepository watermark,
    required ProtectionRepository protection,
  }) : _compression = compression,
       _ocr = ocr,
       _watermark = watermark,
       _protection = protection;

  final CompressionRepository _compression;
  final OcrRepository _ocr;
  final WatermarkRepository _watermark;
  final ProtectionRepository _protection;

  @override
  Future<BatchOutcome> run({
    required BatchAction action,
    required List<int> documentIds,
    Watermark? watermark,
    String? password,
    void Function(int done, int total)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    final items = <BatchItemOutcome>[];

    for (final id in documentIds) {
      if (shouldContinue != null && !shouldContinue()) break;

      items.add(await _runOne(action, id, watermark, password));
      onProgress?.call(items.length, documentIds.length);
    }

    return BatchOutcome(action: action, items: items);
  }

  Future<BatchItemOutcome> _runOne(
    BatchAction action,
    int id,
    Watermark? watermark,
    String? password,
  ) async {
    try {
      return switch (action) {
        BatchAction.compress => await _compressOne(id),
        BatchAction.ocr => await _ocrOne(id),
        BatchAction.watermark => BatchItemOutcome.done(
          id,
          (await _watermark.apply(id, watermark!)).displayName,
        ),
        BatchAction.protect => BatchItemOutcome.done(
          id,
          (await _protection.protect(
            id,
            ProtectRequest(userPassword: password!),
          )).displayName,
        ),
      };
    } on Object catch (e) {
      // Deliberately broad. One malformed document must not abandon the other
      // nine, and the type of failure matters less than finishing the batch.
      // Only the runtime type is recorded - never a message, which could carry
      // a filename or a password.
      return BatchItemOutcome.skipped(
        id,
        BatchSkipReason.failed,
        detail: e.runtimeType.toString(),
      );
    }
  }

  /// Compression that would gain nothing is skipped, not applied.
  ///
  /// A scan gives back close to nothing, and a batch over ten of them would
  /// otherwise create ten near-identical copies. "Already compressed" is
  /// information, not an error.
  Future<BatchItemOutcome> _compressOne(int id) async {
    final result = await _compression.analyse(id);
    if (!result.worthDoing) {
      return BatchItemOutcome.skipped(id, BatchSkipReason.nothingToDo);
    }

    return BatchItemOutcome.done(
      id,
      (await _compression.save(id, result)).displayName,
    );
  }

  /// OCR that recognises nothing throws, and that is a skip rather than a
  /// failure: a document of photographs with no text in them is not broken.
  Future<BatchItemOutcome> _ocrOne(int id) async {
    try {
      return BatchItemOutcome.done(id, (await _ocr.recognise(id)).displayName);
    } on ArgumentError {
      return BatchItemOutcome.skipped(id, BatchSkipReason.nothingToDo);
    }
  }
}
