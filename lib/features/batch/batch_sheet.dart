import 'package:flutter/material.dart';
import 'package:folio/domain/batch/batch_outcome.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Chooses which operation to run over the selected documents.
///
/// Only operations that need no per-document input appear here. Redaction and
/// page edits are deliberately absent: they need boxes or page numbers chosen
/// against each document, and a "batch" that silently applied one document's
/// choices to another would be worse than not offering it.
Future<BatchAction?> showBatchSheet(BuildContext context, int count) {
  return showModalBottomSheet<BatchAction>(
    context: context,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;

      Widget option(
        BatchAction action,
        IconData icon,
        String label, {
        String? subtitle,
      }) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: () => Navigator.of(sheetContext).pop(action),
      );

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                l10n.batchTitle(count),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                l10n.batchNewDocuments,
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ),
            option(BatchAction.compress, Icons.compress, l10n.batchCompress),
            option(
              BatchAction.ocr,
              Icons.text_snippet_outlined,
              l10n.batchOcr,
              subtitle: l10n.batchSlowWarning,
            ),
            option(
              BatchAction.watermark,
              Icons.branding_watermark_outlined,
              l10n.batchWatermark,
            ),
            option(BatchAction.protect, Icons.lock_outline, l10n.batchProtect),
          ],
        ),
      );
    },
  );
}

/// Summarises what a batch actually did.
///
/// "Skipped" is reported separately from "failed" and given its own count. A
/// document that was already well compressed is not an error, and lumping the
/// two together trains people to ignore the errors.
String batchSummary(BatchOutcome outcome, AppLocalizations l10n) {
  if (outcome.producedNothing) return l10n.batchDoneNone;
  if (outcome.everythingWorked) return l10n.batchDoneAll(outcome.succeeded);

  return l10n.batchDoneSome(outcome.succeeded, outcome.skipped);
}

/// The reasons behind the skips, for the detail line.
List<String> batchSkipDetails(BatchOutcome outcome, AppLocalizations l10n) => [
  if (outcome.countOf(BatchSkipReason.nothingToDo) > 0)
    l10n.batchSkipNothing(outcome.countOf(BatchSkipReason.nothingToDo)),
  if (outcome.countOf(BatchSkipReason.failed) > 0)
    l10n.batchSkipFailed(outcome.countOf(BatchSkipReason.failed)),
];
