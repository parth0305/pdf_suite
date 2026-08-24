import 'package:folio/domain/models/library_document.dart';

enum SortField { name, dateAdded, dateOpened, size }

/// Pure sorting. Returns a new list; the input is never mutated.
List<LibraryDocument> sortDocuments(
  List<LibraryDocument> documents, {
  required SortField field,
  required bool ascending,
}) {
  final copy = List<LibraryDocument>.of(documents);

  copy.sort((a, b) {
    final result = switch (field) {
      SortField.name => a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      ),
      SortField.dateAdded => a.addedAt.compareTo(b.addedAt),
      SortField.size => a.sizeBytes.compareTo(b.sizeBytes),
      SortField.dateOpened => _compareNullableDates(
        a.lastOpenedAt,
        b.lastOpenedAt,
      ),
    };
    return ascending ? result : -result;
  });

  return copy;
}

/// Never-opened documents sort as oldest, so that with `ascending: false`
/// (most recent first) they land at the end rather than the top.
int _compareNullableDates(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return a.compareTo(b);
}

List<LibraryDocument> filterDocuments(
  List<LibraryDocument> documents,
  String query,
) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return documents;
  return documents
      .where((d) => d.displayName.toLowerCase().contains(trimmed))
      .toList();
}
