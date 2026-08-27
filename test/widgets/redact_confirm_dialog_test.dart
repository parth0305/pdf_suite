import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/viewer/widgets/redact_confirm_dialog.dart';
import 'package:folio/l10n/app_localizations.dart';

Future<List<bool>> open(WidgetTester tester) async {
  final answers = <bool>[];

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              answers.add(await showRedactConfirmDialog(context, 2)),
          child: const Text('open'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  group('redact confirmation', () {
    // The exclusions are the reason this dialog exists. Someone who believes a
    // redacted document is safe to publish, while their name is still in
    // /Title, was misled by the feature.
    testWidgets('names what redaction does not cover', (tester) async {
      await open(tester);

      expect(find.textContaining('Not covered'), findsOneWidget);
      expect(find.textContaining('title and author'), findsOneWidget);
      expect(find.textContaining('bookmarks'), findsOneWidget);
    });

    testWidgets('says the content cannot be recovered', (tester) async {
      await open(tester);

      expect(find.textContaining('cannot be recovered'), findsOneWidget);
    });

    testWidgets('confirming returns true', (tester) async {
      final answers = await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Redact'));
      await tester.pumpAndSettle();

      expect(answers.single, isTrue);
    });

    testWidgets('cancelling returns false', (tester) async {
      final answers = await open(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(answers.single, isFalse);
    });

    // A dismissed dialog must not read as consent to an irreversible write.
    testWidgets('dismissing returns false, not null-as-yes', (tester) async {
      final answers = await open(tester);

      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();

      expect(answers.single, isFalse);
    });
  });
}
