import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';

LibraryDocument doc({DocumentRef? ref}) => LibraryDocument(
  id: 1,
  ref: ref ?? const ManagedRef(relativePath: 'a.pdf', contentHash: 'h'),
  displayName: 'a.pdf',
  sizeBytes: 10,
  addedAt: DateTime(2026, 8, 24),
  isFavorite: false,
);

void main() {
  group('LibraryDocument', () {
    test('a ManagedRef document is managed', () {
      expect(doc().isManaged, isTrue);
    });

    test('an ExternalRef document is not managed', () {
      final d = doc(
        ref: const ExternalRef(
          handle: PathHandle('/tmp/x.pdf'),
          displayName: 'x.pdf',
        ),
      );
      expect(d.isManaged, isFalse);
    });

    test('copyWith changes only the named fields', () {
      final updated = doc().copyWith(isFavorite: true, displayName: 'b.pdf');

      expect(updated.isFavorite, isTrue);
      expect(updated.displayName, 'b.pdf');
      expect(updated.id, 1);
      expect(updated.sizeBytes, 10);
      expect(updated.addedAt, DateTime(2026, 8, 24));
    });

    test('copyWith leaves untouched fields alone', () {
      final updated = doc().copyWith(pageCount: 3);

      expect(updated.pageCount, 3);
      expect(updated.displayName, 'a.pdf');
      expect(updated.isFavorite, isFalse);
    });

    test('copyWith preserves lastOpenedAt when not supplied', () {
      final opened = doc().copyWith(lastOpenedAt: DateTime(2026, 8, 25));
      final renamed = opened.copyWith(displayName: 'c.pdf');

      expect(renamed.lastOpenedAt, DateTime(2026, 8, 25));
    });
  });
}
