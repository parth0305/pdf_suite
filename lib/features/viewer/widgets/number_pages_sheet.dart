import 'package:flutter/material.dart';
import 'package:folio/domain/numbering/page_numbers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Chooses how pages are numbered.
///
/// The format choices show what they produce rather than naming a style:
/// "Page 7 of 12" says more than "labelled with total".
Future<PageNumbering?> showNumberPagesSheet(BuildContext context) {
  var position = NumberPosition.bottomCentre;
  var format = NumberFormat.plain;
  var skipFirst = false;
  final startAt = TextEditingController(text: '1');

  return showModalBottomSheet<PageNumbering>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;

      return StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.numberPagesMode,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),

                Text(
                  l10n.numberPagesFormat,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                // A dropdown rather than segments: four choices do not fit
                // across a phone, and leaving one out would make a format the
                // engine supports unreachable.
                DropdownButtonFormField<NumberFormat>(
                  initialValue: format,
                  items: [
                    DropdownMenuItem(
                      value: NumberFormat.plain,
                      child: Text(l10n.numberPagesPlain),
                    ),
                    DropdownMenuItem(
                      value: NumberFormat.labelled,
                      child: Text(l10n.numberPagesLabelled),
                    ),
                    DropdownMenuItem(
                      value: NumberFormat.ofTotal,
                      child: Text(l10n.numberPagesOfTotal),
                    ),
                    DropdownMenuItem(
                      value: NumberFormat.labelledOfTotal,
                      child: Text(l10n.numberPagesLabelledOfTotal),
                    ),
                  ],
                  onChanged: (v) => setState(() => format = v ?? format),
                ),
                const SizedBox(height: 16),

                Text(
                  l10n.numberPagesPosition,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                SegmentedButton<NumberPosition>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: NumberPosition.bottomLeft,
                      label: Text(l10n.numberPagesLeft),
                    ),
                    ButtonSegment(
                      value: NumberPosition.bottomCentre,
                      label: Text(l10n.numberPagesCentre),
                    ),
                    ButtonSegment(
                      value: NumberPosition.bottomRight,
                      label: Text(l10n.numberPagesRight),
                    ),
                  ],
                  selected: {position},
                  onSelectionChanged: (v) => setState(() => position = v.first),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value:
                      position == NumberPosition.topLeft ||
                      position == NumberPosition.topCentre ||
                      position == NumberPosition.topRight,
                  title: Text(l10n.numberPagesTop),
                  onChanged: (top) => setState(() {
                    position = switch (position) {
                      NumberPosition.bottomLeft || NumberPosition.topLeft =>
                        top
                            ? NumberPosition.topLeft
                            : NumberPosition.bottomLeft,
                      NumberPosition.bottomRight || NumberPosition.topRight =>
                        top
                            ? NumberPosition.topRight
                            : NumberPosition.bottomRight,
                      _ =>
                        top
                            ? NumberPosition.topCentre
                            : NumberPosition.bottomCentre,
                    };
                  }),
                ),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: skipFirst,
                  title: Text(l10n.numberPagesSkipFirst),
                  onChanged: (v) => setState(() => skipFirst = v),
                ),

                TextField(
                  controller: startAt,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.numberPagesStartAt,
                  ),
                ),
                const SizedBox(height: 16),

                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(
                    PageNumbering(
                      position: position,
                      format: format,
                      skipFirst: skipFirst,
                      // A blank or nonsense box means one, not zero: nobody
                      // numbering pages means to start at nothing.
                      startAt: int.tryParse(startAt.text.trim()) ?? 1,
                    ),
                  ),
                  child: Text(l10n.numberPagesApply),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
