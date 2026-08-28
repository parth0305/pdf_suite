import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Everything the viewer can do to the open document.
enum DocumentAction {
  thumbnails,
  outline,
  fullScreen,
  markup,
  draw,
  insertImage,
  note,
  stamp,
  signature,
  annotations,
  metadata,
  exportImages,
  watermark,
  imageWatermark,
  removeWatermark,
  compress,
  ocr,
  redact,
  protect,
  unlock,
  print,
  share,
}

/// Picks an action, grouped by what it does to the document.
///
/// This replaced a single popup menu of thirteen items. That menu grew one
/// entry per slice until it scrolled, mixed "draw on the page" with "send this
/// to a printer", and hid both under a pencil icon. Sections make it
/// scannable; a bottom sheet suits a phone better than a tall popup.
///
/// The View group appears only on a narrow screen. On a phone the app bar had
/// eight buttons in read mode; thumbnails, outline and full screen move here so
/// three remain. On a tablet or desktop there is room, and they stay in the bar
/// where they are one tap rather than two.
///
/// **Send is separated deliberately.** Print and share are the only two
/// actions that put the document somewhere Folio cannot reach, and the group
/// says so rather than sitting them beside Markup as though they were alike.
Future<DocumentAction?> showDocumentActionsSheet(
  BuildContext context, {
  bool includeView = false,
}) {
  return showModalBottomSheet<DocumentAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      final theme = Theme.of(sheetContext);

      Widget group(String label, {String? note}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (note != null) ...[
              const SizedBox(width: 8),
              Text(
                '· $note',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );

      Widget item(DocumentAction action, IconData icon, String label) =>
          ListTile(
            leading: Icon(icon),
            title: Text(label),
            onTap: () => Navigator.of(sheetContext).pop(action),
          );

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (includeView) ...[
                group(l10n.actionsGroupView),
                item(
                  DocumentAction.thumbnails,
                  Icons.grid_view,
                  l10n.viewerThumbnails,
                ),
                item(DocumentAction.outline, Icons.list, l10n.viewerOutline),
                item(
                  DocumentAction.fullScreen,
                  Icons.fullscreen,
                  l10n.viewerFullScreen,
                ),
              ],
              group(l10n.actionsGroupAnnotate),
              item(
                DocumentAction.markup,
                Icons.format_color_fill,
                l10n.markupMode,
              ),
              item(DocumentAction.draw, Icons.draw_outlined, l10n.drawMode),
              item(
                DocumentAction.insertImage,
                Icons.image_outlined,
                l10n.insertImageMode,
              ),
              item(
                DocumentAction.note,
                Icons.sticky_note_2_outlined,
                l10n.noteMode,
              ),
              item(
                DocumentAction.stamp,
                Icons.approval_outlined,
                l10n.stampMode,
              ),
              item(
                DocumentAction.signature,
                Icons.edit_outlined,
                l10n.signMode,
              ),
              item(
                DocumentAction.annotations,
                Icons.edit_note,
                l10n.annotationsMode,
              ),

              group(l10n.actionsGroupDocument),
              item(
                DocumentAction.metadata,
                Icons.info_outline,
                l10n.metadataMode,
              ),
              item(
                DocumentAction.exportImages,
                Icons.image_outlined,
                l10n.exportImagesMode,
              ),
              item(
                DocumentAction.watermark,
                Icons.branding_watermark_outlined,
                l10n.watermarkMode,
              ),
              item(
                DocumentAction.imageWatermark,
                Icons.photo_size_select_large,
                l10n.watermarkImageMode,
              ),
              item(
                DocumentAction.removeWatermark,
                Icons.layers_clear_outlined,
                l10n.watermarkRemove,
              ),
              item(DocumentAction.compress, Icons.compress, l10n.compressMode),
              item(
                DocumentAction.ocr,
                Icons.text_snippet_outlined,
                l10n.ocrMode,
              ),

              group(l10n.actionsGroupProtect),
              item(
                DocumentAction.protect,
                Icons.lock_outline,
                l10n.protectMode,
              ),
              item(
                DocumentAction.unlock,
                Icons.lock_open_outlined,
                l10n.unlockMode,
              ),
              item(
                DocumentAction.redact,
                Icons.format_color_reset_outlined,
                l10n.redactMode,
              ),

              group(l10n.actionsGroupSend, note: l10n.actionsSendNote),
              item(
                DocumentAction.print,
                Icons.print_outlined,
                l10n.printAction,
              ),
              item(DocumentAction.share, Icons.ios_share, l10n.shareAction),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
