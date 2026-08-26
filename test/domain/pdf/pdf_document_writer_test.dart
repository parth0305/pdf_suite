import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';
import 'package:folio/domain/pdf/pdf_permissions.dart';

const source =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\n'
    'endobj\n'
    'xref\n0 4\n0000000000 65535 f \n'
    'trailer\n<< /Size 4 /Root 1 0 R /Info 9 0 R >>\n'
    'startxref\n9\n%%EOF\n';

List<int> bytesOf(String s) => latin1.encode(s);

String rewritten() => latin1.decode(
  writePdfDocument(bytesOf(source), parsePdfObjects(bytesOf(source))),
);

void main() {
  test('emits every object it was given', () {
    final out = rewritten();

    for (final n in [1, 2, 3]) {
      expect(out, contains('$n 0 obj'), reason: 'object $n');
    }
  });

  test('carries /Root and /Info into the new trailer', () {
    final out = rewritten();

    expect(out, contains('/Root 1 0 R'));
    expect(out, contains('/Info 9 0 R'));
  });

  // This is a rewrite, not an incremental update. A /Prev would point at a
  // cross-reference table that no longer exists in the new file.
  test('the trailer has no /Prev', () {
    expect(rewritten(), isNot(contains('/Prev')));
  });

  test('starts with a PDF header and ends with EOF', () {
    final out = rewritten();

    expect(out.startsWith('%PDF-'), isTrue);
    expect(out.trimRight().endsWith('%%EOF'), isTrue);
  });

  test('the xref offsets point at the objects', () {
    final out = rewritten();
    // Not lastIndexOf('xref') - that matches the one inside `startxref`,
    // which sits after the table.
    final xrefAt = out.lastIndexOf('\nxref\n');
    final entries = RegExp(
      r'^(\d{10}) 00000 n $',
      multiLine: true,
    ).allMatches(out.substring(xrefAt)).toList();

    expect(entries, hasLength(3));
    for (final e in entries) {
      final offset = int.parse(e.group(1)!);
      // An offset that does not land on `N G obj` is a broken xref, and a
      // reader will refuse the file or silently lose the object.
      expect(
        RegExp(r'^\d+ \d+ obj').hasMatch(out.substring(offset)),
        isTrue,
        reason: 'offset $offset should point at an object header',
      );
    }
  });

  test('a document with no objects is refused', () {
    expect(
      () => writePdfDocument(bytesOf('%PDF-1.4\n'), const []),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  test('a document with no /Root is refused', () {
    const noRoot = '1 0 obj\n<< >>\nendobj\ntrailer\n<< /Size 2 >>\n%%EOF\n';
    expect(
      () => writePdfDocument(bytesOf(noRoot), parsePdfObjects(bytesOf(noRoot))),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  group('encrypting', () {
    String encrypted() => latin1.decode(
      writePdfDocument(
        bytesOf(source),
        parsePdfObjects(bytesOf(source)),
        encryption: const PdfEncryption(
          userPassword: 'folio-test',
          handler: PdfSecurityHandler.rc4Revision2,
        ),
      ),
    );

    test('the trailer references an /Encrypt dictionary', () {
      expect(encrypted(), contains('/Encrypt'));
    });

    test('the trailer carries an /ID', () {
      // Revision 2 derives its key from the first /ID element; without one a
      // reader cannot open the document at all.
      expect(encrypted(), contains('/ID [<'));
    });

    // The /Encrypt dictionary and the /ID are what a reader needs BEFORE it
    // can derive a key. Encrypting either produces a file nothing can open.
    test('the /Encrypt dictionary itself is not encrypted', () {
      final out = encrypted();

      expect(out, contains('/Filter /Standard'));
      expect(out, contains('/R 2'));
    });

    test('the password never appears in the output', () {
      expect(encrypted(), isNot(contains('folio-test')));
    });

    test('an unencrypted rewrite has no /Encrypt', () {
      expect(rewritten(), isNot(contains('/Encrypt')));
    });

    // /P is the only permissions value a reader sees in the clear, so a
    // restriction the caller asked for must actually reach the dictionary.
    test('the /Encrypt dictionary carries the requested /P', () {
      final out = latin1.decode(
        writePdfDocument(
          bytesOf(source),
          parsePdfObjects(bytesOf(source)),
          encryption: PdfEncryption(
            userPassword: 'pw',
            permissions: const PdfPermissions(copying: false).bits,
          ),
        ),
      );

      expect(out, contains('/P ${const PdfPermissions(copying: false).bits}'));
      expect(
        out,
        isNot(contains('/P ${PdfPermissions.all.bits}')),
        reason: 'the default must not be substituted for the request',
      );
    });

    test('a distinct owner password changes /O without changing /U', () {
      List<int> bytes({String? owner}) => writePdfDocument(
        bytesOf(source),
        parsePdfObjects(bytesOf(source)),
        encryption: PdfEncryption(
          userPassword: 'reader',
          ownerPassword: owner,
          randomBytes: (n) => List<int>.generate(n, (i) => (i * 7) & 0xFF),
        ),
      );

      String entry(String key, List<int> raw) {
        final text = latin1.decode(raw);
        final at = text.indexOf('$key <');
        return text.substring(at, text.indexOf('>', at));
      }

      final without = bytes();
      final with_ = bytes(owner: 'author');

      expect(entry('/U', with_), entry('/U', without));
      expect(entry('/O', with_), isNot(entry('/O', without)));
    });
  });

  // Two IDENTICAL strings inside ONE document must encrypt differently. This
  // is the only thing that observes a reused initialisation vector: a repeated
  // IV still decrypts correctly, so no render assertion can ever see it.
  test('identical strings in one document encrypt differently', () {
    var counter = 0;
    const twins =
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /T (repeated value) >>\n'
        'endobj\n'
        '4 0 obj\n<< /Type /Annot /Contents (repeated value) >>\nendobj\n'
        'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

    final out = latin1.decode(
      writePdfDocument(
        bytesOf(twins),
        parsePdfObjects(bytesOf(twins)),
        // A VARYING source, as production uses. A constant one would make
        // collisions correct behaviour and prove nothing.
        encryption: PdfEncryption(
          userPassword: 'folio-test',
          randomBytes: (n) => List<int>.generate(n, (_) => counter++ & 0xFF),
        ),
      ),
      allowInvalid: true,
    );

    // Objects only. The trailer's /ID deliberately writes the same value
    // twice, which would otherwise read as a collision.
    final objectsOnly = out.substring(0, out.indexOf('\ntrailer'));
    final ciphertexts = RegExp(
      r'<([0-9a-f]{32,})>',
    ).allMatches(objectsOnly).map((m) => m.group(1)!).toList();

    expect(ciphertexts.length, greaterThanOrEqualTo(2));
    expect(
      ciphertexts.toSet().length,
      ciphertexts.length,
      reason: 'identical plaintext must not produce identical ciphertext',
    );
  });
}
