// Pure PDF fixture construction, shared by the host-side generator
// (scripts/make_fixtures.dart) and the on-device integration tests.
//
// Deliberately dependency-free so it can run anywhere.
import 'dart:convert';

typedef PageSpec = ({String title, String body});

/// Writes object bodies, then a correct xref table and trailer.
List<int> assemble(
  List<String> objects,
  String trailerDict, {
  bool corruptXref = false,
}) {
  final out = <int>[...latin1.encode('%PDF-1.4\n')];
  final offsets = <int>[];

  for (var n = 0; n < objects.length; n++) {
    offsets.add(out.length);
    out.addAll(latin1.encode('${n + 1} 0 obj\n${objects[n]}\nendobj\n'));
  }

  final xrefStart = out.length;
  out.addAll(
    latin1.encode('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n'),
  );
  for (final off in offsets) {
    final value = corruptXref ? (off + 917) : off;
    out.addAll(
      latin1.encode('${value.toString().padLeft(10, '0')} 00000 n \n'),
    );
  }
  out.addAll(
    latin1.encode('trailer\n$trailerDict\nstartxref\n$xrefStart\n%%EOF\n'),
  );
  return out;
}

/// A minimal but valid PDF: catalog, page tree, one content stream per page,
/// and a Helvetica font resource.
List<int> buildPdf(
  List<PageSpec> pages, {
  bool corruptXref = false,
  String? extraCatalogEntries,
  bool omitText = false,
}) {
  final objects = <String>[];
  objects.add('<< /Type /Catalog /Pages 2 0 R${extraCatalogEntries ?? ''} >>');

  final kids = List.generate(pages.length, (i) => '${3 + i * 2} 0 R').join(' ');
  objects.add('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>');

  final fontObj = 3 + pages.length * 2;
  for (var i = 0; i < pages.length; i++) {
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
      '/Resources << /Font << /F1 $fontObj 0 R >> >> '
      '/Contents ${4 + i * 2} 0 R >>',
    );
    // omitText produces a page with no text-showing operators at all, so text
    // extraction correctly returns empty - the "scanned document" case.
    final stream = omitText
        ? '0.9 0.9 0.9 rg 40 40 515 762 re f\n'
        : 'BT /F1 24 Tf 60 760 Td (${pages[i].title}) Tj ET\n'
              'BT /F1 12 Tf 60 700 Td (${pages[i].body}) Tj ET\n'
              'BT /F1 10 Tf 60 60 Td (Page ${i + 1} of ${pages.length}) Tj ET\n';
    objects.add('<< /Length ${stream.length} >>\nstream\n${stream}endstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  return assemble(
    objects,
    '<< /Size ${objects.length + 1} /Root 1 0 R >>',
    corruptXref: corruptXref,
  );
}

List<PageSpec> generatedPages(int count) => List.generate(
  count,
  (i) => (
    title: 'Section ${i + 1}',
    body: 'Generated body text for page ${i + 1}.',
  ),
);

/// The canonical sample document.
///
/// Integration tests assert on `PLATYPUS-TOKEN-42` and `Appendix A`.
/// **Do not change these strings.**
const List<PageSpec> kSampleThreePage = [
  (
    title: 'Confidential Invoice',
    body: 'Acme Corporation - Total due: 48500 rupees - REDACT-ME-9931',
  ),
  (
    title: 'Terms and Conditions',
    body: 'Payment due within thirty days of receipt. Late fees apply.',
  ),
  (
    title: 'Appendix A',
    body: 'Searchable marker string: PLATYPUS-TOKEN-42 appears only here.',
  ),
];

/// A catalog /Names entry carrying JavaScript. The app must open a document
/// containing this without executing anything.
const String kJavaScriptNames =
    r' /Names << /JavaScript << /Names [(evil) << /S /JavaScript '
    r'/JS (app.alert\(1\);) >>] >> >>';
