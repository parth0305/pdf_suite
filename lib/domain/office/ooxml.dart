/// Pieces every Office format needs.
library;

/// The XML declaration OOXML parts begin with.
const xmlHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

/// Text made safe to put inside an XML element.
///
/// An ampersand in a document's own text otherwise produces a part that is not
/// XML, and Word refuses the whole file rather than the paragraph.
String escapeXml(String text) {
  final buffer = StringBuffer();

  for (final rune in text.runes) {
    buffer.write(switch (rune) {
      0x26 => '&amp;',
      0x3C => '&lt;',
      0x3E => '&gt;',
      0x22 => '&quot;',
      0x27 => '&apos;',
      // Control characters are not permitted in XML at all, and a PDF's text
      // layer can carry them. Tab, newline and return are the exceptions.
      _ when rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D => '',
      _ => String.fromCharCode(rune),
    });
  }

  return buffer.toString();
}

/// The package relationships part, which is how a reader finds anything.
String packageRelationships(String type, String target) =>
    '$xmlHeader'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006'
    '/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org'
    '/officeDocument/2006/relationships/$type" Target="$target"/>'
    '</Relationships>';

/// A spreadsheet column's letters: 1 is A, 27 is AA.
String columnName(int index) {
  var remaining = index;
  final letters = StringBuffer();

  while (remaining > 0) {
    // Spreadsheet columns are not base 26: there is no zero digit, so the
    // remainder has to be taken from one less than the number.
    final digit = (remaining - 1) % 26;
    letters.write(String.fromCharCode(65 + digit));
    remaining = (remaining - 1) ~/ 26;
  }

  return letters.toString().split('').reversed.join();
}
