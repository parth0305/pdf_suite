import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/widgets/adaptive_scaffold.dart';

Widget _harness(Size size) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    home: AdaptiveScaffold(
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [
        AdaptiveDestination(icon: Icon(Icons.folder), label: 'Library'),
        AdaptiveDestination(icon: Icon(Icons.settings), label: 'Settings'),
      ],
      body: const Text('body'),
    ),
  ),
);

void main() {
  group('AdaptiveScaffold', () {
    testWidgets('compact width uses bottom navigation', (tester) async {
      await tester.pumpWidget(_harness(const Size(400, 800)));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('medium width uses a navigation rail', (tester) async {
      await tester.pumpWidget(_harness(const Size(800, 1000)));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('expanded width uses an extended rail', (tester) async {
      await tester.pumpWidget(_harness(const Size(1400, 900)));
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('body is rendered at every width class', (tester) async {
      for (final size in const [
        Size(400, 800),
        Size(800, 1000),
        Size(1400, 900),
      ]) {
        await tester.pumpWidget(_harness(size));
        expect(find.text('body'), findsOneWidget);
      }
    });
  });
}
