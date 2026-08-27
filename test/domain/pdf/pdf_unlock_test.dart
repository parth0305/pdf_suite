import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_decryption.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';
import 'package:folio/domain/pdf/pdf_unlock.dart';

const source =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
    '/Contents 4 0 R >>\nendobj\n'
    '4 0 obj\n<< /Length 24 >>\nstream\nSECRET-CONTENT-INSIDE\nendstream\n'
    'endobj\n'
    '9 0 obj\n<< /Title (SECRET-TITLE) >>\nendobj\n'
    'xref\n0 10\n0000000000 65535 f \n'
    'trailer\n<< /Size 10 /Root 1 0 R /Info 9 0 R >>\nstartxref\n9\n%%EOF\n';

Uint8List locked({
  required String password,
  PdfSecurityHandler handler = PdfSecurityHandler.aesRevision6,
}) => writePdfDocument(
  latin1.encode(source),
  parsePdfObjects(latin1.encode(source)),
  encryption: PdfEncryption(userPassword: password, handler: handler),
);

void main() {
  group('AES-256 (revision 6)', () {
    // Folio locks documents; it should be able to unlock them again. A tool
    // that can only add protection is lopsided.
    test('the content comes back', () {
      final out = latin1.decode(
        unlockPdf(locked(password: 'open-me'), 'open-me'),
        allowInvalid: true,
      );

      expect(out, contains('SECRET-CONTENT-INSIDE'));
    });

    // Strings are encrypted too. A /Title left encrypted reads as mojibake in
    // every viewer's properties panel.
    test('strings come back, not just streams', () {
      final out = latin1.decode(
        unlockPdf(locked(password: 'open-me'), 'open-me'),
        allowInvalid: true,
      );

      expect(out, contains('SECRET-TITLE'));
    });

    test('the document no longer says it is encrypted', () {
      final out = latin1.decode(
        unlockPdf(locked(password: 'open-me'), 'open-me'),
        allowInvalid: true,
      );

      expect(out, isNot(contains('/Encrypt')));
      expect(out, isNot(contains('/Filter /Standard')));
    });

    test('the owner password also opens it', () {
      final marked = writePdfDocument(
        latin1.encode(source),
        parsePdfObjects(latin1.encode(source)),
        encryption: const PdfEncryption(
          userPassword: 'reader',
          ownerPassword: 'author',
        ),
      );

      expect(
        latin1.decode(unlockPdf(marked, 'author'), allowInvalid: true),
        contains('SECRET-CONTENT-INSIDE'),
      );
    });

    test('the wrong password is refused', () {
      expect(
        () => unlockPdf(locked(password: 'open-me'), 'not-it'),
        throwsA(isA<WrongPassword>()),
      );
    });
  });

  group('RC4 (revision 2)', () {
    test('the content comes back', () {
      final out = latin1.decode(
        unlockPdf(
          locked(password: 'open-me', handler: PdfSecurityHandler.rc4Revision2),
          'open-me',
        ),
        allowInvalid: true,
      );

      expect(out, contains('SECRET-CONTENT-INSIDE'));
    });

    // Revision 2 derives a key per object; revision 6 uses the file key
    // directly. Getting that backwards produces a document nothing can open.
    test('per-object keys are used, not the file key', () {
      final info = readEncryptionInfo(
        latin1.decode(
          locked(password: 'x', handler: PdfSecurityHandler.rc4Revision2),
          allowInvalid: true,
        ),
      )!;

      expect(info.usesPerObjectKeys, isTrue);
      expect(info.revision, 2);
    });
  });

  group('refusals', () {
    test('a document that is not protected is refused', () {
      expect(
        () => unlockPdf(Uint8List.fromList(latin1.encode(source)), 'x'),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });

    test('the refusal says the document is not protected', () {
      expect(
        () => unlockPdf(Uint8List.fromList(latin1.encode(source)), 'x'),
        throwsA(
          isA<UnsupportedPdfStructure>().having(
            (e) => e.technicalDetail,
            'technicalDetail',
            contains('not password protected'),
          ),
        ),
      );
    });
  });

  test('a locked then unlocked document reads as the original did', () {
    final out = latin1.decode(
      unlockPdf(locked(password: 'round-trip'), 'round-trip'),
      allowInvalid: true,
    );

    expect(out, contains('/Type /Catalog'));
    expect(out, contains('/Type /Page'));
    expect(out, contains('SECRET-CONTENT-INSIDE'));
    expect(out, contains('/Root 1 0 R'));
  });
}
