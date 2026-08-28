import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/text_edit.dart';
import 'package:folio/features/viewer/widgets/text_edit_dialog.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Opens the dialog. The box fills once it closes, so a test can drive the
/// widgets first and read the answer afterwards.
Future<List<String?>> open(
  WidgetTester tester, {
  String original = 'Total 48500',
  required Future<EditPlan> Function(String) check,
}) async {
  final captured = <String?>[];

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => captured.add(
            await showTextEditDialog(context, original: original, check: check),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

Future<EditPlan> allowed(String _) async =>
    const EditPatch(start: 0, end: 0, replacement: [], adjustment: 0);

void main() {
  group('editing text', () {
    testWidgets('starts with what the page already says', (tester) async {
      await open(tester, check: allowed);

      expect(find.text('Total 48500'), findsOneWidget);
    });

    testWidgets('returns the new text', (tester) async {
      final captured = await open(tester, check: allowed);

      await tester.enterText(find.byType(TextField), 'Total 52000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(captured.single, 'Total 52000');
    });

    testWidgets('cancelling returns nothing', (tester) async {
      final captured = await open(tester, check: allowed);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(captured.single, isNull);
    });

    // Told while still looking at the characters, rather than after the
    // dialog has closed.
    testWidgets('a refusal appears as the text is typed', (tester) async {
      await open(
        tester,
        check: (value) async => value.contains('5')
            ? const EditRefused(EditRefusal.missingCharacters, detail: ['5'])
            : const EditPatch(start: 0, end: 0, replacement: [], adjustment: 0),
      );

      await tester.enterText(find.byType(TextField), 'Total 5');
      await tester.pumpAndSettle();

      expect(find.textContaining('no 5 in it'), findsOneWidget);
    });

    testWidgets('a refused replacement cannot be applied', (tester) async {
      await open(
        tester,
        check: (_) async =>
            const EditRefused(EditRefusal.missingCharacters, detail: ['5']),
      );

      await tester.enterText(find.byType(TextField), 'Total 5');
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a refusal clears when the text is fixed', (tester) async {
      await open(
        tester,
        check: (value) async => value.contains('5')
            ? const EditRefused(EditRefusal.missingCharacters, detail: ['5'])
            : const EditPatch(start: 0, end: 0, replacement: [], adjustment: 0),
      );

      await tester.enterText(find.byType(TextField), 'Total 5');
      await tester.pumpAndSettle();
      expect(find.textContaining('no 5 in it'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Total 2');
      await tester.pumpAndSettle();

      expect(find.textContaining('no 5 in it'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    // Each reason has to say something the person can act on.
    testWidgets('an overrun says how far over it is', (tester) async {
      await open(
        tester,
        check: (_) async =>
            const EditRefused(EditRefusal.wouldOverlap, detail: ['4.2 points']),
      );

      await tester.enterText(find.byType(TextField), 'much longer');
      await tester.pumpAndSettle();

      expect(find.textContaining('4.2 points'), findsOneWidget);
    });

    testWidgets('invisible text explains why changing it is pointless', (
      tester,
    ) async {
      await open(
        tester,
        check: (_) async => const EditRefused(EditRefusal.notVisible),
      );

      await tester.enterText(find.byType(TextField), 'anything');
      await tester.pumpAndSettle();

      expect(find.textContaining('invisible'), findsOneWidget);
    });

    testWidgets('a font with no widths says so', (tester) async {
      await open(
        tester,
        check: (_) async => const EditRefused(EditRefusal.unknownWidths),
      );

      await tester.enterText(find.byType(TextField), 'anything');
      await tester.pumpAndSettle();

      expect(find.textContaining('how wide'), findsOneWidget);
    });

    // Typing the original back is not a change and must not be reported as a
    // problem. The text has to be changed FIRST: setting a field to what it
    // already holds notifies nobody, so a test that only types the original
    // never reaches this at all.
    testWidgets('typing the original back clears the refusal', (tester) async {
      await open(
        tester,
        check: (_) async =>
            const EditRefused(EditRefusal.missingCharacters, detail: ['5']),
      );

      await tester.enterText(find.byType(TextField), 'Total 5');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Total 48500');
      await tester.pumpAndSettle();

      expect(find.textContaining('no 5 in it'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });
  });
}
