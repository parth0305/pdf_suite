import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/services/edited_name.dart';

void main() {
  group('editedName', () {
    test('appends (edited) before the extension', () {
      expect(editedName('Invoice.pdf'), 'Invoice (edited).pdf');
    });

    // Without this, repeated edits produce "(edited) (edited) (edited)".
    test('a second edit numbers rather than repeating the suffix', () {
      expect(editedName('Invoice (edited).pdf'), 'Invoice (edited 2).pdf');
    });

    test('numbering continues past two', () {
      expect(editedName('Invoice (edited 2).pdf'), 'Invoice (edited 3).pdf');
      expect(editedName('Invoice (edited 9).pdf'), 'Invoice (edited 10).pdf');
    });

    test('a name with no extension still works', () {
      expect(editedName('Invoice'), 'Invoice (edited)');
    });

    test('a name containing dots keeps the final extension', () {
      expect(editedName('2026.01.invoice.pdf'), '2026.01.invoice (edited).pdf');
    });

    test(
      'the word edited elsewhere in the name is not treated as a suffix',
      () {
        expect(editedName('edited notes.pdf'), 'edited notes (edited).pdf');
      },
    );
  });

  group('extractedName', () {
    test('names a single extracted page', () {
      expect(extractedName('Invoice.pdf', 1), 'Invoice (1 page).pdf');
    });

    test('names several extracted pages', () {
      expect(extractedName('Invoice.pdf', 3), 'Invoice (3 pages).pdf');
    });
  });

  group('splitPartName', () {
    test('numbers each part', () {
      expect(splitPartName('Invoice.pdf', 1), 'Invoice (part 1).pdf');
      expect(splitPartName('Invoice.pdf', 12), 'Invoice (part 12).pdf');
    });
  });
}
