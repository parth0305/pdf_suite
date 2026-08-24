import 'package:flutter/material.dart';
import 'package:folio/core/constants/breakpoints.dart';

class AdaptiveDestination {
  const AdaptiveDestination({required this.icon, required this.label});
  final Widget icon;
  final String label;
}

/// Single navigation shell for all platforms. Chooses its layout from the
/// available width, never from the host platform.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final widthClass = widthClassFor(MediaQuery.sizeOf(context).width);

    if (widthClass == WidthClass.compact) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: d.icon, label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: widthClass == WidthClass.expanded,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: widthClass == WidthClass.expanded
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(icon: d.icon, label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
