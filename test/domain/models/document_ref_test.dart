import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/models/document_ref.dart';

void main() {
  group('DocumentRef encoding', () {
    test('ManagedRef survives a round trip', () {
      const ref = ManagedRef(
        relativePath: 'a1b2/invoice.pdf',
        contentHash: 'deadbeef',
      );
      final decoded = DocumentRef.decode(ref.encode());

      expect(decoded, isA<ManagedRef>());
      final m = decoded as ManagedRef;
      expect(m.relativePath, 'a1b2/invoice.pdf');
      expect(m.contentHash, 'deadbeef');
    });

    test('ExternalRef with a path handle survives a round trip', () {
      const ref = ExternalRef(
        handle: PathHandle(r'C:\Users\a\Documents\x.pdf'),
        displayName: 'x.pdf',
      );
      final decoded = DocumentRef.decode(ref.encode()) as ExternalRef;

      expect(decoded.displayName, 'x.pdf');
      expect(
        (decoded.handle as PathHandle).path,
        r'C:\Users\a\Documents\x.pdf',
      );
    });

    test('ExternalRef with a bookmark handle preserves the bytes exactly', () {
      final bytes = Uint8List.fromList([0, 1, 2, 250, 255]);
      final ref = ExternalRef(
        handle: BookmarkHandle(bytes),
        displayName: 'y.pdf',
      );
      final decoded = DocumentRef.decode(ref.encode()) as ExternalRef;

      expect((decoded.handle as BookmarkHandle).data, bytes);
    });

    test('ExternalRef with a content URI survives a round trip', () {
      const ref = ExternalRef(
        handle: ContentUriHandle(
          'content://com.android.providers/document/1234',
        ),
        displayName: 'z.pdf',
      );
      final decoded = DocumentRef.decode(ref.encode()) as ExternalRef;

      expect((decoded.handle as ContentUriHandle).uri, contains('content://'));
    });

    test('decoding malformed input throws FormatException', () {
      expect(
        () => DocumentRef.decode('not-json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decoding a valid JSON non-object throws FormatException', () {
      expect(
        () => DocumentRef.decode('[1,2,3]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decoding an unknown kind throws FormatException', () {
      expect(
        () => DocumentRef.decode('{"kind":"martian"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
