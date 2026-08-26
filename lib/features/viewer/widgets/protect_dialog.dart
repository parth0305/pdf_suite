import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Collects a password twice, returning it only when both entries match.
///
/// Nothing here is logged: a password is the most sensitive value the app
/// handles, and a document protected with a typo is unrecoverable.
Future<String?> showProtectDialog(BuildContext context) {
  final first = TextEditingController();
  final second = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;

      return StatefulBuilder(
        builder: (context, setState) {
          final password = first.text;
          final matches = password.isNotEmpty && password == second.text;

          return AlertDialog(
            title: Text(l10n.protectMode),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: first,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(labelText: l10n.protectPassword),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: second,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.protectConfirm,
                    errorText: second.text.isNotEmpty && !matches
                        ? l10n.protectMismatch
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.protectWarning,
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
                onPressed: matches
                    ? () => Navigator.of(dialogContext).pop(password)
                    : null,
                child: Text(l10n.protectApply),
              ),
            ],
          );
        },
      );
    },
  );
}
