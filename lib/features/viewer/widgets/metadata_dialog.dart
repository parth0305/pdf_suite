import 'package:flutter/material.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Edits a document's title, author, subject and keywords.
///
/// Folio has always carried metadata through every operation; this is the
/// first way to change it. The note is not decoration: metadata travels with a
/// document, and redaction deliberately does not touch it, which is the one
/// thing about it most likely to surprise someone.
Future<PdfMetadata?> showMetadataDialog(
  BuildContext context,
  PdfMetadata current,
) {
  final title = TextEditingController(text: current.title ?? '');
  final author = TextEditingController(text: current.author ?? '');
  final subject = TextEditingController(text: current.subject ?? '');
  final keywords = TextEditingController(text: current.keywords ?? '');

  String? valueOf(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  return showDialog<PdfMetadata>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;

      return StatefulBuilder(
        builder: (context, setState) {
          final edited = PdfMetadata(
            title: valueOf(title),
            author: valueOf(author),
            subject: valueOf(subject),
            keywords: valueOf(keywords),
            // Folio never writes a /Creator of its own: a document you edit
            // does not start advertising which tool touched it.
            creator: current.creator,
          );

          Widget field(String label, TextEditingController controller) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: label),
                  onChanged: (_) => setState(() {}),
                ),
              );

          return AlertDialog(
            title: Text(l10n.metadataMode),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(l10n.metadataTitle, title),
                  field(l10n.metadataAuthor, author),
                  field(l10n.metadataSubject, subject),
                  field(l10n.metadataKeywords, keywords),
                  Text(
                    l10n.metadataNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancelAction),
              ),
              FilledButton(
                // Writing nothing would produce a duplicate document with no
                // change in it.
                onPressed: edited.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(edited),
                child: Text(l10n.metadataSave),
              ),
            ],
          );
        },
      );
    },
  );
}
