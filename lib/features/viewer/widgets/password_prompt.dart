import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Returns the entered password, or null if the user cancelled.
///
/// The value is handed straight to the engine and is never logged or persisted.
Future<String?> promptForPassword(BuildContext context) {
  final controller = TextEditingController();
  final l10n = AppLocalizations.of(context)!;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(l10n.passwordPromptTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(labelText: l10n.passwordPromptHint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(l10n.passwordPromptOpen),
        ),
      ],
    ),
  );
}
