import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/features/viewer/annotation_edit_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Every annotation on the current page, one row each.
///
/// Tapping is not enough on its own: annotations overlap, and a thin ink
/// stroke is hard to hit. The list also makes it discoverable that an
/// annotation Folio cannot restyle is still deletable, rather than leaving the
/// colour controls mysteriously inert.
class AnnotationListPanel extends ConsumerWidget {
  const AnnotationListPanel({required this.pageIndex, super.key});

  final int pageIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(annotationEditProvider);
    final controller = ref.read(annotationEditProvider.notifier);
    final onPage = state.session.onPage(pageIndex);

    if (onPage.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.annotationsEmpty,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: onPage.length,
      itemBuilder: (context, i) {
        final a = onPage[i];
        final staged = state.session.styleOf(a.objectNumber);
        final colour = staged?.colorArgb ?? a.colorArgb;

        return ListTile(
          selected: state.selectedObjectNumber == a.objectNumber,
          leading: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colour == null ? null : Color(colour),
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          title: Text(a.subtype),
          subtitle: a.restylable ? null : Text(l10n.annotationsDeleteOnly),
          onTap: () => controller.select(a.objectNumber),
        );
      },
    );
  }
}
