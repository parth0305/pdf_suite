import 'package:flutter/material.dart';
import 'package:folio/domain/editing/text_edit.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Types a replacement for one run of text, and says at once when it cannot
/// be used.
///
/// The refusal appears as the person types rather than after they press save.
/// Being told a character is unavailable while still looking at it is a
/// different experience from being told once the dialog has closed.
Future<String?> showTextEditDialog(
  BuildContext context, {
  required String original,
  required Future<EditPlan> Function(String replacement) check,
}) {
  final controller = TextEditingController(text: original);
  EditPlan? plan;
  var checking = false;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      final theme = Theme.of(dialogContext);

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> recheck(String value) async {
            if (value == original) {
              setState(() => plan = null);
              return;
            }

            setState(() => checking = true);
            final result = await check(value);
            if (!dialogContext.mounted) return;

            setState(() {
              plan = result;
              checking = false;
            });
          }

          final refusal = plan is EditRefused ? plan! as EditRefused : null;

          return AlertDialog(
            title: Text(l10n.editTextTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l10n.editTextLabel),
                  onChanged: recheck,
                ),
                if (refusal != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _explain(refusal, l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancelAction),
              ),
              FilledButton(
                onPressed: refusal != null || checking
                    ? null
                    : () => Navigator.of(dialogContext).pop(controller.text),
                child: Text(l10n.editTextApply),
              ),
            ],
          );
        },
      );
    },
  );
}

/// What to say, in terms of what the person can do about it.
String _explain(EditRefused refusal, AppLocalizations l10n) =>
    switch (refusal.reason) {
      // The characters are named, because "this font cannot write that" is
      // not actionable and "there is no 5 in this font" is.
      EditRefusal.missingCharacters => l10n.editTextMissingCharacters(
        refusal.detail.join(' '),
      ),
      EditRefusal.wouldOverlap => l10n.editTextWouldOverlap(
        refusal.detail.isEmpty ? '' : refusal.detail.first,
      ),
      EditRefusal.unknownWidths => l10n.editTextUnknownWidths,
      EditRefusal.unreadable => l10n.editTextUnreadable,
      EditRefusal.notVisible => l10n.editTextNotVisible,
    };
