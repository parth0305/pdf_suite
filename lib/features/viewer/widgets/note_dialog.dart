import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Collects a note's text, both when placing one and when editing one.
///
/// Returns the trimmed text, or null if cancelled. Empty text keeps Save
/// disabled: an icon that says nothing only clutters the page.
Future<String?> showNoteDialog(
  BuildContext context, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final l10n = AppLocalizations.of(context)!;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.noteText),
      content: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(
            hintText: l10n.noteHint,
            helperText: value.text.trim().isEmpty ? l10n.noteEmpty : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.cancelAction),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(value.text.trim()),
            child: Text(l10n.markupSave),
          ),
        ),
      ],
    ),
  );
}
