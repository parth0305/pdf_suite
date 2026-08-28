import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:folio/domain/pdf/pdf_encryption.dart';
import '../scripts/pdf_fixture_builder.dart';

/// Builds a fixture on the device and returns its path.
///
/// Integration tests execute on the device, so a host-relative path such as
/// `test_documents/x.pdf` does not resolve. Rather than shipping fixtures as
/// assets - which would bake megabytes of test data into release builds - they
/// are generated on device using the same pure builder the host script uses.
Future<String> fixturePath(String name) async {
  final dir = await getTemporaryDirectory();
  final target = File('${dir.path}/$name');
  if (target.existsSync()) return target.path;

  await target.writeAsBytes(_build(name), flush: true);
  return target.path;
}

List<int> _build(String name) {
  switch (name) {
    case 'sample_3page.pdf':
      return buildPdf(kSampleThreePage);
    case 'scanned_no_text.pdf':
      return buildPdf(generatedPages(3), omitText: true);
    case 'malformed_xref.pdf':
      return buildPdf(generatedPages(3), corruptXref: true);
    case 'embedded_javascript.pdf':
      return buildPdf(generatedPages(1), extraCatalogEntries: kJavaScriptNames);
    case 'encrypted_user_pw.pdf':
      return _encrypted('folio-test', -44);
    case 'no_copy_permission.pdf':
      return _encrypted('', -48);
    case 'with_metadata.pdf':
      return buildPdf(
        kSampleThreePage,
        infoDict:
            '<< /Title (FOLIO-PROBE-TITLE) /Author (FOLIO-PROBE-AUTHOR) '
            '/Subject (FOLIO-PROBE-SUBJECT) >>',
      );
    case 'membership_form.pdf':
      return buildFormPdf();
    case 'corrupt_truncated.pdf':
      final full = buildPdf(generatedPages(3));
      return full.sublist(0, full.length - 200);
    default:
      final match = RegExp(r'^pages_(\d+)\.pdf$').firstMatch(name);
      if (match != null) {
        return buildPdf(generatedPages(int.parse(match.group(1)!)));
      }
      throw ArgumentError('unknown fixture: $name');
  }
}

List<int> _encrypted(String password, int permissions) => buildEncryptedPdf(
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

/// Pumps until [finder] matches, or gives up after [timeout].
///
/// `pumpAndSettle(Duration)` takes the pump INTERVAL, not a timeout, so it
/// settles as soon as no frame is scheduled - which on a slow device happens
/// long before an async document load has finished. Waiting for the widget
/// that the load produces is the only thing that actually means "ready".
///
/// The timeout is a pathology bound: 30 seconds means something is wrong, not
/// that the device is busy.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw StateError('timed out waiting for a widget to appear');
}

/// Pumps until the `IconButton` wrapping [icon] is actually tappable.
///
/// `find.byIcon` matches a DISABLED button just as happily as an enabled one,
/// so waiting for the icon to exist proves nothing: the tap lands on a button
/// whose onPressed is null and silently does nothing. A toolbar button can
/// stay disabled long after the page count arrives - the viewer's search
/// button waits for the searcher, not the document.
Future<void> pumpUntilEnabled(
  WidgetTester tester,
  IconData icon, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  final buttons = find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(IconButton),
  );

  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (buttons.evaluate().isNotEmpty &&
        tester.widget<IconButton>(buttons.first).onPressed != null) {
      return;
    }
  }
  throw StateError('timed out waiting for a button to become enabled');
}

/// Pumps until [condition] holds, or throws when it never does.
///
/// `pumpAndSettle` returns once the widget tree is idle, which says nothing
/// about work still running in a repository. Rasterising a page at 200 DPI
/// outlives a settled frame comfortably, and asserting straight after the tap
/// checks a state the app has not reached yet.
Future<void> pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  throw StateError('timed out waiting for a condition to hold');
}
