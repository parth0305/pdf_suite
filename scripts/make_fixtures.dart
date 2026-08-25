// Generates test fixtures into test_documents/ for host-side inspection and
// for the fixture-generator test. Integration tests build their own fixtures
// on-device via the same builder, so no test data ships in release builds.
import 'dart:io';

import 'pdf_encrypt.dart';
import 'pdf_fixture_builder.dart';

void write(String name, List<int> bytes) {
  final f = File('test_documents/$name')..writeAsBytesSync(bytes);
  stdout.writeln('  ${name.padRight(28)} ${f.lengthSync()} bytes');
}

void main() {
  Directory('test_documents').createSync(recursive: true);
  stdout.writeln('Generating fixtures:');

  // The integration tests assert on PLATYPUS-TOKEN-42 and "Appendix A".
  // Do not change these strings.
  write('sample_3page.pdf', buildPdf(kSampleThreePage));

  for (final n in const [1, 10, 100, 500, 1000, 5000]) {
    write('pages_$n.pdf', buildPdf(generatedPages(n)));
  }

  write('scanned_no_text.pdf', buildPdf(generatedPages(3), omitText: true));

  // Valid objects, every xref offset wrong.
  write('malformed_xref.pdf', buildPdf(generatedPages(3), corruptXref: true));

  // Must open without executing anything.
  write(
    'embedded_javascript.pdf',
    buildPdf(generatedPages(1), extraCatalogEntries: kJavaScriptNames),
  );

  // Truncated: %%EOF and part of the xref removed.
  final full = buildPdf(generatedPages(3));
  write('corrupt_truncated.pdf', full.sublist(0, full.length - 200));

  // Encrypted fixtures. ISO 32000-1 Table 22 numbers permission bits from 1.
  // Bit 3 (value 4) is copy; bit 5 (value 16) is print.
  //   -44 = 0xFFFFFFD4 -> bit3 set, bit5 set  : print + copy allowed
  //   -48 = 0xFFFFFFD0 -> bit3 clear, bit5 set: print allowed, copy denied
  List<int> encrypted(String password, int permissions) => buildEncryptedPdf(
    kSampleThreePage,
    userPassword: password,
    permissions: permissions,
    ownerValue: (o, u) => computeOwnerValue(ownerPassword: o, userPassword: u),
    encryptionKey: computeEncryptionKey,
    userValue: computeUserValue,
    objectKey: objectKey,
    rc4: rc4,
    hexString: hexString,
  );

  // Integration tests expect exactly this password.
  write('encrypted_user_pw.pdf', encrypted('folio-test', -44));

  // Opens with no prompt (empty user password) but forbids copying, so the
  // copy-restriction path can be exercised without a password dialog.
  write('no_copy_permission.pdf', encrypted('', -48));

  stdout.writeln('Done.');
}
