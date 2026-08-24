import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
