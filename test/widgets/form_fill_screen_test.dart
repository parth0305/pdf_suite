import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/forms/form_field.dart' as forms;
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/form_repository.dart';
import 'package:folio/features/forms/form_fill_screen.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/viewer/form_providers.dart';
import 'package:folio/l10n/app_localizations.dart';

const _rect = TextRect(left: 0, bottom: 0, right: 200, top: 24);

forms.FormWidget widget(int number) =>
    forms.FormWidget(objectNumber: number, pageIndex: 0, rect: _rect);

final _document = LibraryDocument(
  id: 1,
  ref: const ManagedRef(relativePath: 'a/form.pdf', contentHash: 'hash'),
  displayName: 'Form.pdf',
  sizeBytes: 10,
  pageCount: 1,
  addedAt: DateTime(2026, 8, 28),
  isFavorite: false,
);

class _FakeForms implements FormRepository {
  _FakeForms(this._fields);

  final List<forms.FormField> _fields;
  Map<String, String?>? filled;

  @override
  Future<List<forms.FormField>> fields(int documentId) async => _fields;

  @override
  Future<LibraryDocument> fill(
    int documentId,
    Map<String, String?> values,
  ) async {
    filled = values;
    return _document;
  }
}

/// The library list reloads after a save. Only [all] is ever reached from
/// this screen; anything else being called is a change worth failing on.
class _FakeLibrary implements LibraryRepository {
  @override
  Future<List<LibraryDocument>> all() async => [_document];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<_FakeForms> _open(
  WidgetTester tester,
  List<forms.FormField> fields,
) async {
  final repository = _FakeForms(fields);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        formRepositoryProvider.overrideWithValue(repository),
        libraryRepositoryProvider.overrideWithValue(_FakeLibrary()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FormFillScreen(document: _document),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  group('form fill screen', () {
    testWidgets('a text field shows the value the document already has', (
      tester,
    ) async {
      await _open(tester, [
        forms.FormField(
          name: 'full name',
          kind: forms.FormFieldKind.text,
          objectNumber: 5,
          widgets: [widget(5)],
          value: 'Priya',
        ),
      ]);

      expect(find.text('Priya'), findsOneWidget);
    });

    // The value is only in the controller until save. A screen that reads its
    // map instead drops every field the user did not leave.
    testWidgets('typing into a field is saved', (tester) async {
      final repository = await _open(tester, [
        forms.FormField(
          name: 'full name',
          kind: forms.FormFieldKind.text,
          objectNumber: 5,
          widgets: [widget(5)],
        ),
      ]);

      await tester.enterText(find.byType(TextField), 'Ravi');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.filled, {'full name': 'Ravi'});
    });

    testWidgets('a checkbox saves the state its own document names', (
      tester,
    ) async {
      final repository = await _open(tester, [
        const forms.FormField(
          name: 'newsletter',
          kind: forms.FormFieldKind.checkBox,
          objectNumber: 7,
          widgets: [
            forms.FormWidget(
              objectNumber: 7,
              pageIndex: 0,
              rect: _rect,
              onState: 'On',
            ),
          ],
          options: ['On'],
        ),
      ]);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.filled, {'newsletter': 'On'});
    });

    testWidgets('a radio group offers every button', (tester) async {
      await _open(tester, [
        forms.FormField(
          name: 'plan',
          kind: forms.FormFieldKind.radio,
          objectNumber: 8,
          widgets: [widget(9), widget(10)],
          options: ['Basic', 'Premium'],
        ),
      ]);

      expect(find.text('Basic'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
    });

    // A person picks "India"; the form's owner reads "IN".
    testWidgets('a choice saves the export value behind the label', (
      tester,
    ) async {
      final repository = await _open(tester, [
        const forms.FormField(
          name: 'country',
          kind: forms.FormFieldKind.choice,
          objectNumber: 11,
          widgets: [],
          options: ['India', 'United Kingdom'],
          exports: ['IN', 'GB'],
        ),
      ]);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('India').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.filled, {'country': 'IN'});
    });

    // Shown, not hidden: a read-only field is information the form is giving.
    testWidgets('a read-only field is shown and cannot be typed into', (
      tester,
    ) async {
      await _open(tester, [
        const forms.FormField(
          name: 'issued on',
          kind: forms.FormFieldKind.text,
          objectNumber: 12,
          widgets: [],
          value: '2026-08-28',
          flags: 1,
        ),
      ]);

      expect(find.text('issued on'), findsOneWidget);
      expect(find.text('2026-08-28'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a signature field says it is left alone', (tester) async {
      await _open(tester, [
        const forms.FormField(
          name: 'signed by',
          kind: forms.FormFieldKind.signature,
          objectNumber: 17,
          widgets: [],
        ),
      ]);

      expect(find.textContaining('leaves this alone'), findsOneWidget);
    });

    testWidgets('a required field is marked as one', (tester) async {
      await _open(tester, [
        forms.FormField(
          name: 'full name',
          kind: forms.FormFieldKind.text,
          objectNumber: 5,
          widgets: [widget(5)],
          flags: 2,
        ),
      ]);

      expect(find.text('full name *'), findsOneWidget);
    });

    testWidgets('a length limit is applied to what can be typed', (
      tester,
    ) async {
      await _open(tester, [
        forms.FormField(
          name: 'membership number',
          kind: forms.FormFieldKind.text,
          objectNumber: 6,
          widgets: [widget(6)],
          maxLength: 8,
        ),
      ]);

      await tester.enterText(find.byType(TextField), '1234567890123');
      await tester.pumpAndSettle();

      expect(find.text('123456789012'), findsNothing);
    });

    // A form that recalculates in another reader will not recalculate here.
    testWidgets('the screen says what it does not do', (tester) async {
      await _open(tester, [
        forms.FormField(
          name: 'total',
          kind: forms.FormFieldKind.text,
          objectNumber: 5,
          widgets: [widget(5)],
        ),
      ]);

      expect(find.textContaining('will not recalculate'), findsOneWidget);
    });

    testWidgets('a document with no form says so, and offers no save', (
      tester,
    ) async {
      await _open(tester, []);

      expect(find.text('No form here'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });
  });
}
