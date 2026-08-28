import 'package:flutter/material.dart';
import 'package:folio/domain/crop/page_crop.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Chooses how much to trim off each side.
///
/// Margins are in millimetres. Points are the PDF's unit and nobody measures a
/// margin in them; the conversion belongs here rather than in the reader's
/// head.
Future<PageMargins?> showCropSheet(
  BuildContext context, {
  required Future<PageMargins> Function() onDetect,
}) {
  final fields = {
    for (final side in _Side.values) side: TextEditingController(text: '0'),
  };
  var detecting = false;

  return showModalBottomSheet<PageMargins>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;

      double value(_Side side) =>
          double.tryParse(fields[side]!.text.trim()) ?? 0;

      return StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.cropMode,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),

                for (final row in const [
                  [_Side.top, _Side.bottom],
                  [_Side.left, _Side.right],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        for (final side in row)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: side == row.first ? 12 : 0,
                              ),
                              child: TextField(
                                controller: fields[side],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: switch (side) {
                                    _Side.top => l10n.cropTop,
                                    _Side.bottom => l10n.cropBottom,
                                    _Side.left => l10n.cropLeft,
                                    _Side.right => l10n.cropRight,
                                  },
                                  suffixText: l10n.cropMillimetres,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                OutlinedButton.icon(
                  onPressed: detecting
                      ? null
                      : () async {
                          setState(() => detecting = true);
                          final found = await onDetect();
                          if (!sheetContext.mounted) return;

                          setState(() {
                            detecting = false;
                            for (final side in _Side.values) {
                              fields[side]!.text = pointsToMm(switch (side) {
                                _Side.top => found.top,
                                _Side.bottom => found.bottom,
                                _Side.left => found.left,
                                _Side.right => found.right,
                              }).toStringAsFixed(1);
                            }
                          });
                        },
                  icon: const Icon(Icons.content_cut),
                  label: Text(l10n.cropDetect),
                ),
                const SizedBox(height: 16),

                // Said plainly, because "crop" sounds like "delete" and is
                // not: the margins are hidden, and everything in them is
                // still in the file.
                Text(
                  l10n.cropKeepsContent,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),

                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(
                    PageMargins(
                      top: mmToPoints(value(_Side.top)),
                      bottom: mmToPoints(value(_Side.bottom)),
                      left: mmToPoints(value(_Side.left)),
                      right: mmToPoints(value(_Side.right)),
                    ),
                  ),
                  child: Text(l10n.cropApply),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

enum _Side { top, bottom, left, right }
