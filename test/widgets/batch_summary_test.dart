import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/batch/batch_outcome.dart';
import 'package:folio/features/batch/batch_sheet.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Resolves the real localisations, so the wording under test is the wording
/// a user sees.
Future<AppLocalizations> l10n(WidgetTester tester) async {
  late AppLocalizations resolved;

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          resolved = AppLocalizations.of(context)!;
          return const SizedBox();
        },
      ),
    ),
  );

  return resolved;
}

BatchOutcome outcomeOf({int done = 0, int nothingToDo = 0, int failed = 0}) =>
    BatchOutcome(
      action: BatchAction.compress,
      items: [
        for (var i = 0; i < done; i++) BatchItemOutcome.done(i, 'Doc $i.pdf'),
        for (var i = 0; i < nothingToDo; i++)
          BatchItemOutcome.skipped(100 + i, BatchSkipReason.nothingToDo),
        for (var i = 0; i < failed; i++)
          BatchItemOutcome.skipped(200 + i, BatchSkipReason.failed),
      ],
    );

void main() {
  testWidgets('all succeeded reads as a clean result', (tester) async {
    final strings = await l10n(tester);

    expect(batchSummary(outcomeOf(done: 5), strings), contains('5'));
    expect(batchSkipDetails(outcomeOf(done: 5), strings), isEmpty);
  });

  // A progress bar that ends with "Done" when three of ten failed is a lie.
  testWidgets('a partial result says how many were skipped', (tester) async {
    final strings = await l10n(tester);
    final outcome = outcomeOf(done: 7, failed: 3);

    expect(batchSummary(outcome, strings), contains('7'));
    expect(batchSummary(outcome, strings), contains('3'));
  });

  // "Already compressed" is information, not an error. Reporting it as a
  // failure trains people to ignore failures.
  testWidgets('nothing-to-gain is counted apart from failure', (tester) async {
    final strings = await l10n(tester);
    final details = batchSkipDetails(
      outcomeOf(done: 1, nothingToDo: 4, failed: 2),
      strings,
    );

    expect(details, hasLength(2));
    expect(details.first, contains('4'));
    expect(details.first.toLowerCase(), contains('nothing to gain'));
    expect(details.last, contains('2'));
    expect(details.last.toLowerCase(), contains('could not be processed'));
  });

  testWidgets('only the reasons that occurred are listed', (tester) async {
    final strings = await l10n(tester);

    expect(
      batchSkipDetails(outcomeOf(done: 1, nothingToDo: 2), strings),
      hasLength(1),
    );
  });

  testWidgets('a batch that produced nothing says so', (tester) async {
    final strings = await l10n(tester);

    expect(
      batchSummary(outcomeOf(nothingToDo: 3), strings).toLowerCase(),
      contains('nothing was produced'),
    );
  });

  testWidgets('an empty batch is not reported as success', (tester) async {
    final strings = await l10n(tester);

    expect(
      batchSummary(outcomeOf(), strings).toLowerCase(),
      contains('nothing was produced'),
    );
  });
}
