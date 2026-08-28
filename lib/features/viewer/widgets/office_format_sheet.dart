import 'package:flutter/material.dart';
import 'package:folio/core/theme/app_theme.dart';
import 'package:folio/domain/repositories/office_export_repository.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Chooses which Office format to convert to, and says what conversion does
/// not carry across.
///
/// The caveat is at the top rather than buried: someone expecting their
/// document to arrive looking the same should read that before choosing, not
/// after opening the result.
Future<OfficeFormat?> showOfficeFormatSheet(BuildContext context) {
  return showModalBottomSheet<OfficeFormat>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      final theme = Theme.of(sheetContext);

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space * 2,
                0,
                AppTheme.space * 2,
                AppTheme.space * 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.officeMode, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppTheme.space),
                  Text(
                    l10n.officeReconstructed,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            for (final entry in [
              (OfficeFormat.word, Icons.description_outlined, l10n.officeWord),
              (OfficeFormat.excel, Icons.grid_on, l10n.officeExcel),
              (
                OfficeFormat.powerPoint,
                Icons.slideshow_outlined,
                l10n.officePowerPoint,
              ),
            ])
              ListTile(
                leading: Icon(entry.$2),
                title: Text(entry.$3),
                onTap: () => Navigator.of(sheetContext).pop(entry.$1),
              ),
            const SizedBox(height: AppTheme.space * 2),
          ],
        ),
      );
    },
  );
}
