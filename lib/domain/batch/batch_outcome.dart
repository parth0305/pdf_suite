/// What a batch operation is doing to each document.
enum BatchAction { compress, ocr, watermark, protect }

/// Why one document in a batch did not produce a result.
///
/// "Skipped" is not "failed": a document already well compressed, or one with
/// no text to recognise, is a perfectly good outcome that produced no new
/// file. Reporting those as errors would train people to ignore the errors.
enum BatchSkipReason { nothingToDo, alreadyProtected, unsupported, failed }

/// One document's result.
class BatchItemOutcome {
  const BatchItemOutcome.done(this.documentId, this.resultName)
    : skipped = null,
      detail = null;

  const BatchItemOutcome.skipped(
    this.documentId,
    BatchSkipReason reason, {
    this.detail,
  }) : skipped = reason,
       resultName = null;

  final int documentId;

  /// The new document's name, when one was produced.
  final String? resultName;

  final BatchSkipReason? skipped;

  /// A short technical note for the failure case. Never a password, never a
  /// document's contents.
  final String? detail;

  bool get succeeded => skipped == null;
}

/// The result of running a batch to completion.
///
/// A batch NEVER aborts on the first error. Stopping halfway leaves the user
/// with some documents processed and no record of which, which is worse than
/// either finishing or not starting.
class BatchOutcome {
  const BatchOutcome({required this.action, required this.items});

  final BatchAction action;
  final List<BatchItemOutcome> items;

  int get succeeded => items.where((i) => i.succeeded).length;
  int get skipped => items.where((i) => !i.succeeded).length;

  int countOf(BatchSkipReason reason) =>
      items.where((i) => i.skipped == reason).length;

  /// True when nothing at all was produced, which deserves different wording
  /// from a partial success.
  bool get producedNothing => succeeded == 0;

  bool get everythingWorked => skipped == 0 && items.isNotEmpty;
}
