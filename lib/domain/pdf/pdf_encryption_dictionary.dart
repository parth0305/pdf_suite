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
