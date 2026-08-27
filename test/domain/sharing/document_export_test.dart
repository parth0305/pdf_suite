import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/sharing/document_export.dart';

DocumentExport exportOf(String name) =>
    DocumentExport(bytes: Uint8List(0), displayName: name, isProtected: false);

void main() {
  group('fileName', () {
    test('an ordinary name passes through', () {
      expect(exportOf('Invoice.pdf').fileName, 'Invoice.pdf');
    });

    test('a missing extension is added', () {
      expect(exportOf('Invoice').fileName, 'Invoice.pdf');
    });

    test('an uppercase extension is not doubled', () {
      expect(exportOf('Invoice.PDF').fileName, 'Invoice.PDF');
    });

    // A display name is user-supplied text, and sharing turns it into a
    // filename in another application's world.
    test('path separators are stripped', () {
      expect(exportOf('../../etc/passwd').fileName, isNot(contains('/')));
      expect(exportOf(r'a\b\c.pdf').fileName, isNot(contains(r'\')));
    });

    test('control characters are stripped', () {
      expect(exportOf('bad\u0007name.pdf').fileName, 'bad_name.pdf');
    });

    test('characters Windows refuses are stripped', () {
      expect(exportOf('a:b*c?.pdf').fileName, 'a_b_c_.pdf');
    });

    test('a name that is entirely unusable still yields a filename', () {
      expect(exportOf('   ').fileName, 'document.pdf');
      expect(exportOf('///').fileName, isNotEmpty);
    });
  });

  group('looksEncrypted', () {
    String trailerWith(String entries) =>
        '%PDF-1.4\ntrailer\n<< /Size 9 /Root 1 0 R $entries >>\n'
        'startxref\n9\n%%EOF\n';

    test('an /Encrypt in the trailer is encryption', () {
      expect(looksEncrypted(trailerWith('/Encrypt 8 0 R')), isTrue);
    });

    test('a document with no /Encrypt is not', () {
      expect(looksEncrypted(trailerWith('')), isFalse);
    });

    // The string can occur inside a compressed stream by coincidence. Refusing
    // to print because of a byte pattern in an image would be a failure the
    // user could never explain.
    test('/Encrypt in a stream is not encryption', () {
      const text =
          '%PDF-1.4\n'
          '4 0 obj\n<< /Length 20 >>\nstream\nxx/Encrypt 9 0 Rxx\nendstream\n'
          'endobj\n'
          'trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      expect(looksEncrypted(text), isFalse);
    });

    test('an incremental update that added encryption is found', () {
      const text =
          '%PDF-1.4\ntrailer\n<< /Size 9 /Root 1 0 R >>\n'
          'startxref\n9\n%%EOF\n'
          'trailer\n<< /Size 12 /Root 1 0 R /Encrypt 11 0 R /Prev 9 >>\n'
          'startxref\n900\n%%EOF\n';

      expect(looksEncrypted(text), isTrue);
    });
  });
}
