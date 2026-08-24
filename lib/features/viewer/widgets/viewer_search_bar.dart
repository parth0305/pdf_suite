import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

class ViewerSearchBar extends StatefulWidget {
  const ViewerSearchBar({
    super.key,
    required this.searcher,
    required this.onClose,
  });

  final PdfTextSearcher searcher;
  final VoidCallback onClose;

  @override
  State<ViewerSearchBar> createState() => _ViewerSearchBarState();
}

class _ViewerSearchBarState extends State<ViewerSearchBar> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searcher = widget.searcher;
    final total = searcher.matches.length;
    final current = searcher.currentIndex;
    final hasQuery = _field.text.trim().isNotEmpty;

    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _field,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.viewerSearch,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value.trim().isEmpty) {
                    searcher.resetTextSearch();
                  } else {
                    searcher.startTextSearch(value, caseInsensitive: true);
                  }
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              !hasQuery
                  ? ''
                  : total == 0
                  ? l10n.viewerNoMatches
                  : l10n.viewerMatchIndicator((current ?? 0) + 1, total),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            IconButton(
              tooltip: l10n.viewerPreviousMatch,
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: !searcher.hasMatches || current == null || current == 0
                  ? null
                  : () => searcher.goToMatch(searcher.matches[current - 1]),
            ),
            IconButton(
              tooltip: l10n.viewerNextMatch,
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed:
                  !searcher.hasMatches ||
                      current == null ||
                      current >= total - 1
                  ? null
                  : () => searcher.goToMatch(searcher.matches[current + 1]),
            ),
            IconButton(
              tooltip: l10n.viewerCloseSearch,
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}
