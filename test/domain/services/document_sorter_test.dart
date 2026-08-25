import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/services/document_sorter.dart';

LibraryDocument doc(
  String name, {
  int size = 100,
  DateTime? added,
  DateTime? opened,
}) => LibraryDocument(
  id: name.hashCode,
  ref: ManagedRef(relativePath: name, contentHash: name),
  displayName: name,
  sizeBytes: size,
  addedAt: added ?? DateTime(2026),
  lastOpenedAt: opened,
  isFavorite: false,
);

void main() {
  group('sortDocuments', () {
    test('sorts by name case-insensitively', () {
      final result = sortDocuments(
        [doc('banana.pdf'), doc('Apple.pdf'), doc('cherry.pdf')],
        field: SortField.name,
        ascending: true,
      );
      expect(result.map((d) => d.displayName), [
        'Apple.pdf',
        'banana.pdf',
        'cherry.pdf',
      ]);
    });

    test('reverses when ascending is false', () {
      final result = sortDocuments(
        [doc('a.pdf'), doc('b.pdf')],
        field: SortField.name,
        ascending: false,
      );
      expect(result.first.displayName, 'b.pdf');
    });

    test('sorts by size', () {
      final result = sortDocuments(
        [doc('big.pdf', size: 900), doc('small.pdf', size: 10)],
        field: SortField.size,
        ascending: true,
      );
      expect(result.first.displayName, 'small.pdf');
    });

    test('sorts by date added', () {
      final result = sortDocuments(
        [
          doc('new.pdf', added: DateTime(2026, 8, 20)),
          doc('old.pdf', added: DateTime(2026, 1, 1)),
        ],
        field: SortField.dateAdded,
        ascending: true,
      );
      expect(result.first.displayName, 'old.pdf');
    });

    // The rule that is easy to get backwards: with "most recent first",
    // never-opened documents must sink to the bottom, not float to the top.
    test('never-opened documents sort last when showing most-recent-first', () {
      final result = sortDocuments(
        [doc('never.pdf'), doc('opened.pdf', opened: DateTime(2026, 5, 1))],
        field: SortField.dateOpened,
        ascending: false,
      );
      expect(result.first.displayName, 'opened.pdf');
      expect(result.last.displayName, 'never.pdf');
    });

    test('two never-opened documents compare equal', () {
      final result = sortDocuments(
        [doc('a.pdf'), doc('b.pdf')],
        field: SortField.dateOpened,
        ascending: false,
      );
      expect(result, hasLength(2));
    });

    test('does not mutate the input list', () {
      final input = [doc('b.pdf'), doc('a.pdf')];
      sortDocuments(input, field: SortField.name, ascending: true);
      expect(input.first.displayName, 'b.pdf');
    });
  });

  group('filterDocuments', () {
    test('matches case-insensitively on a substring', () {
      final result = filterDocuments([
        doc('Invoice March.pdf'),
        doc('notes.pdf'),
      ], 'invoice');
      expect(result, hasLength(1));
    });

    test('an empty query returns everything', () {
      expect(filterDocuments([doc('a.pdf'), doc('b.pdf')], ''), hasLength(2));
    });

    test('a whitespace-only query returns everything', () {
      expect(
        filterDocuments([doc('a.pdf'), doc('b.pdf')], '   '),
        hasLength(2),
      );
    });

    test('no match returns empty', () {
      expect(filterDocuments([doc('a.pdf')], 'zzz'), isEmpty);
    });
  });
}
