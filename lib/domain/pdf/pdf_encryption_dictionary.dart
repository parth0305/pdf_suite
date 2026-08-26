import 'package:folio/domain/pdf/pdf_encryption.dart';

/// The standard security handler dictionary, revision 2.
///
/// This shape is not a guess: it matches `encrypted_user_pw.pdf`, a fixture
/// PDFium opens today.
String encryptionDictionary({
  required List<int> ownerValue,
  required List<int> userValue,
  required int permissions,
}) =>
    '<< /Filter /Standard /V 1 /R 2 '
    '/O ${hexString(ownerValue)} '
    '/U ${hexString(userValue)} '
    '/P $permissions >>';

/// The standard security handler dictionary, revision 6 (AES-256).
///
/// /StmF and /StrF both name the same crypt filter: in V5 the file key
/// encrypts streams and strings alike, with no per-object derivation.
String aesEncryptionDictionary({
  required List<int> u,
  required List<int> ue,
  required List<int> o,
  required List<int> oe,
  required List<int> perms,
  required int permissions,
}) =>
    '<< /Filter /Standard /V 5 /R 6 /Length 256 '
    '/CF << /StdCF << /CFM /AESV3 /Length 32 /AuthEvent /DocOpen >> >> '
    '/StmF /StdCF /StrF /StdCF '
    '/U ${hexString(u)} /UE ${hexString(ue)} '
    '/O ${hexString(o)} /OE ${hexString(oe)} '
    '/Perms ${hexString(perms)} '
    '/P $permissions /EncryptMetadata true >>';
