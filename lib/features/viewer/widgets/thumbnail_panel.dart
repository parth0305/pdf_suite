import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

/// Lazily rendered page thumbnails.
///
/// Uses a builder-based list so only visible thumbnails are rendered and
/// off-screen bitmaps are released - required by the memory rules in brief
/// section 11 for 1000-page documents.
class ThumbnailPanel extends StatelessWidget {
  const ThumbnailPanel({
    super.key,
    required this.document,
    required this.currentPage,
    required this.onJump,
  });

  final PdfDocument document;
  final int currentPage;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return ListView.builder(
      itemCount: document.pages.length,
      itemExtent: 172,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;
        final isCurrent = pageNumber == currentPage;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Semantics(
            label: l10n.viewerPageLabel(pageNumber),
            selected: isCurrent,
            button: true,
            child: InkWell(
              onTap: () => onJump(pageNumber),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isCurrent
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: isCurrent ? 2 : 1,
                        ),
                      ),
                      child: PdfPageView(
                        document: document,
                        pageNumber: pageNumber,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$pageNumber',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isCurrent ? scheme.primary : null,
                      fontWeight: isCurrent ? FontWeight.bold : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
