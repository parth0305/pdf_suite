import 'package:flutter/material.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/l10n/app_localizations.dart';

class FlatOutlineEntry {
  const FlatOutlineEntry({
    required this.title,
    required this.pageIndex,
    required this.depth,
  });

  final String title;
  final int? pageIndex;
  final int depth;
}

/// Depth-first flattening so the outline renders as an indented list rather
/// than nested expanders, which are awkward on a phone.
List<FlatOutlineEntry> flattenOutline(
  List<OutlineNode> nodes, {
  int depth = 0,
}) {
  final result = <FlatOutlineEntry>[];
  for (final node in nodes) {
    result.add(
      FlatOutlineEntry(
        title: node.title,
        pageIndex: node.pageIndex,
        depth: depth,
      ),
    );
    result.addAll(flattenOutline(node.children, depth: depth + 1));
  }
  return result;
}

class OutlinePanel extends StatelessWidget {
  const OutlinePanel({super.key, required this.nodes, required this.onJump});

  final List<OutlineNode> nodes;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final flat = flattenOutline(nodes);

    if (flat.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.viewerNoOutline, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.builder(
      itemCount: flat.length,
      itemBuilder: (context, i) {
        final entry = flat[i];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(
            left: 16.0 + entry.depth * 16,
            right: 16,
          ),
          title: Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          enabled: entry.pageIndex != null,
          onTap: entry.pageIndex == null
              ? null
              : () => onJump(entry.pageIndex!),
        );
      },
    );
  }
}
