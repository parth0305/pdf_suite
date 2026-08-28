import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// What the user chose to export.
class ExportImagesRequest {
  const ExportImagesRequest({required this.range, required this.dpi});

  final String range;
  final int dpi;
}

/// Chooses a page range and a resolution.
///
/// The resolutions are named for what they are for rather than by number:
/// nobody choosing between images thinks in dots per inch, and "Print" says
/// more than "300".
Future<ExportImagesRequest?> showExportImagesDialog(BuildContext context) {
  final range = TextEditingController();
  var dpi = 150;

  return showDialog<ExportImagesRequest>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;

      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.exportImagesMode),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: range,
                decoration: InputDecoration(
                  labelText: l10n.exportImagesRange,
                  hintText: '1-3, 7',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.exportImagesQuality,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 96, label: Text(l10n.exportImagesLow)),
                  ButtonSegment(
                    value: 150,
                    label: Text(l10n.exportImagesMedium),
                  ),
                  ButtonSegment(value: 300, label: Text(l10n.exportImagesHigh)),
                ],
                selected: {dpi},
                onSelectionChanged: (v) => setState(() => dpi = v.first),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.exportImagesNote,
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
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(ExportImagesRequest(range: range.text, dpi: dpi)),
              child: Text(l10n.exportImagesAction),
            ),
          ],
        ),
      );
    },
  );
}
