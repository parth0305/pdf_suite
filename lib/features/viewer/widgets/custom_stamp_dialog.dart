import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Collects the wording for a custom stamp, or offers today's date.
///
/// A date stamp is not a separate mechanism: it is this dialog with the date
/// already filled in. One code path, one appearance, one thing to test.
Future<String?> showCustomStampDialog(BuildContext context) {
  final controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;

      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.stampCustom),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: l10n.stampCustomLabel),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text(l10n.stampDate),
                  onPressed: () => setState(
                    () => controller.text = formatStampDate(DateTime.now()),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              // A stamp reading nothing is not a stamp.
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(l10n.stampApply),
            ),
          ],
        ),
      );
    },
  );
}

/// A date a person would write, not an ISO timestamp.
///
/// Deliberately not localised beyond English, which is the only language Folio
/// ships: a half-translated date is worse than a plainly English one.
String formatStampDate(DateTime at) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${at.day} ${months[at.month - 1]} ${at.year}';
}
