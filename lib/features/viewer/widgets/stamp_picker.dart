import 'package:flutter/material.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/l10n/app_localizations.dart';

/// The six presets, each in its own colour.
class StampPicker extends StatelessWidget {
  const StampPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final StampPreset selected;
  final ValueChanged<StampPreset> onSelected;

  static String labelFor(StampPreset preset, AppLocalizations l10n) =>
      switch (preset) {
        StampPreset.approved => l10n.stampApproved,
        StampPreset.rejected => l10n.stampRejected,
        StampPreset.draft => l10n.stampDraft,
        StampPreset.confidential => l10n.stampConfidential,
        StampPreset.reviewed => l10n.stampReviewed,
        StampPreset.urgent => l10n.stampUrgent,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in StampPreset.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(labelFor(preset, l10n)),
                selected: selected == preset,
                onSelected: (_) => onSelected(preset),
                side: BorderSide(
                  color: Color(
                    Stamp(
                      preset: preset,
                      pageIndex: 0,
                      anchorPt: const PdfPoint(0, 0),
                    ).colorArgb,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
