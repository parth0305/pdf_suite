import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Asks for the password that opens a protected document.
///
/// Only one field, unlike protecting: this password already exists, so there
/// is nothing to confirm against. A wrong one is refused by the document
/// itself, which is a better check than asking twice.
Future<String?> showUnlockDialog(BuildContext context) {
  final controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;

      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.unlockMode),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.unlockPrompt),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              // The result has no password at all. Saying so matters: someone
              // may expect "remove password" to mean "change it".
              Text(
                l10n.unlockNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: controller.text.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(l10n.unlockAction),
            ),
          ],
        ),
      );
    },
  );
}
