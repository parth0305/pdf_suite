import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/models/protect_request.dart';
import 'package:folio/features/viewer/widgets/protect_dialog.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Opens the dialog. The returned box is filled once the dialog pops, so a
/// test can drive the widgets first and read the result afterwards.
Future<List<ProtectRequest?>> _open(WidgetTester tester) async {
  final captured = <ProtectRequest?>[];

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => captured.add(await showProtectDialog(context)),
          child: const Text('open'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

Future<void> _typePasswords(WidgetTester tester, String password) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), password);
  await tester.pump();
  await tester.enterText(fields.at(1), password);
  await tester.pump();
}

void main() {
  group('protect dialog', () {
    testWidgets('will not submit until both passwords match', (tester) async {
      await _open(tester);

      final apply = find.widgetWithText(FilledButton, 'Protect');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      await tester.enterText(find.byType(TextField).at(0), 'secret');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(apply).onPressed,
        isNull,
        reason: 'one field filled is not a confirmed password',
      );

      await tester.enterText(find.byType(TextField).at(1), 'secret');
      await tester.pump();
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    });

    testWidgets('restrictions are hidden until asked for', (tester) async {
      await _open(tester);

      expect(find.text('Restrict what readers can do'), findsOneWidget);
      expect(
        find.byType(CheckboxListTile),
        findsNothing,
        reason: 'the section starts collapsed',
      );

      await tester.tap(find.text('Restrict what readers can do'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNWidgets(4));
    });

    testWidgets('everything is permitted by default', (tester) async {
      final captured = await _open(tester);

      await _typePasswords(tester, 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Protect'));
      await tester.pumpAndSettle();

      expect(captured.single!.userPassword, 'secret');
      expect(captured.single!.permissions.printing, isTrue);
      expect(captured.single!.permissions.copying, isTrue);
      expect(
        captured.single!.distinctOwnerPassword,
        isNull,
        reason: 'an empty owner field must not record a second password',
      );
    });

    testWidgets('unticking a box denies that permission', (tester) async {
      final captured = await _open(tester);

      await _typePasswords(tester, 'secret');
      await tester.tap(find.text('Restrict what readers can do'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Printing'));
      await tester.pumpAndSettle();

      // The owner password lives inside the same section, so this also checks
      // it survives the expansion.
      await tester.enterText(find.byType(TextField).at(2), 'author');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Protect'));
      await tester.pumpAndSettle();

      expect(captured.single!.permissions.printing, isFalse);
      expect(
        captured.single!.permissions.copying,
        isTrue,
        reason: 'only the box that was ticked off may change',
      );
      expect(captured.single!.distinctOwnerPassword, 'author');
    });

    testWidgets('an owner password equal to the user one is not recorded', (
      tester,
    ) async {
      expect(
        const ProtectRequest(
          userPassword: 'same',
          ownerPassword: 'same',
        ).distinctOwnerPassword,
        isNull,
      );
    });
  });
}
