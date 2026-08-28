import 'package:flutter/material.dart';
import 'package:folio/domain/archive/pdfa_check.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Says whether a document can be archived, and what conversion will change.
///
/// Both halves matter. A refusal that does not name the font in the way leaves
/// someone with nothing to act on; a conversion that quietly drops an attached
/// file is a surprise found much later.
Future<bool> showArchiveDialog(BuildContext context, PdfaReport report) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      final theme = Theme.of(dialogContext);

      String describe(PdfaIssue issue) => switch (issue) {
        PdfaIssue.fontNotEmbedded => l10n.archiveFontNotEmbedded,
        PdfaIssue.encrypted => l10n.archiveEncrypted,
        PdfaIssue.xrefStream => l10n.archiveUnsupportedStructure,
        PdfaIssue.lzwCompression => l10n.archiveLzw,
        PdfaIssue.externalStream => l10n.archiveExternalStream,
        PdfaIssue.javaScript => l10n.archiveRemovesJavaScript,
        PdfaIssue.embeddedFile => l10n.archiveRemovesAttachments,
        PdfaIssue.needAppearances => l10n.archiveRemovesNeedAppearances,
      };

      return AlertDialog(
        title: Text(
          report.canConvert ? l10n.archiveTitle : l10n.archiveCannotTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report.canConvert ? l10n.archiveBody : l10n.archiveCannotBody),
            for (final blocker in report.blockers.entries) ...[
              const SizedBox(height: 12),
              Text(describe(blocker.key), style: theme.textTheme.bodyMedium),
              // The names, not just the count: "Helvetica, Times-Roman" is
              // something a person can go and fix.
              Text(
                blocker.value.toSet().join(', '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            if (report.canConvert && report.removals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.archiveWillRemove, style: theme.textTheme.bodySmall),
              for (final removal in report.removals)
                Text(
                  '• ${describe(removal)}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(report.canConvert ? l10n.cancelAction : l10n.okAction),
          ),
          if (report.canConvert)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.archiveConfirm),
            ),
        ],
      );
    },
  );

  return confirmed ?? false;
}
