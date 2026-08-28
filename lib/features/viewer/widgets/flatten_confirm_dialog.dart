import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Confirms flattening, and says plainly what stops being possible afterwards.
///
/// Flattening is the one annotation operation that cannot be undone from
/// inside the document it produces. Saying so is cheaper than a support
/// question from someone who wanted to move a signature afterwards.
Future<bool> showFlattenConfirmDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;

      return AlertDialog(
        title: Text(l10n.flattenConfirmTitle),
        content: Text(l10n.flattenConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.flattenConfirm),
          ),
        ],
      );
    },
  );

  // Dismissing the dialog is not consent.
  return confirmed ?? false;
}
