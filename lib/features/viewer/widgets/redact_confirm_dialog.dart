import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Confirms applying redactions, and says what redaction does NOT cover.
///
/// The exclusions are not fine print. Someone who believes a redacted document
/// is safe to publish, when their name is still in `/Title`, has been misled by
/// the feature rather than by their own carelessness.
Future<bool> showRedactConfirmDialog(BuildContext context, int boxCount) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      final theme = Theme.of(dialogContext);

      return AlertDialog(
        title: Text(l10n.redactConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.redactConfirmBody),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.redactConfirmNotCovered,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.redactConfirmAction),
          ),
        ],
      );
    },
  );

  // Dismissing the dialog is not consent.
  return confirmed ?? false;
}
