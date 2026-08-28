import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/office/ooxml.dart';
import 'package:folio/domain/office/text_structure.dart';
import 'package:folio/domain/office/zip_writer.dart';

/// One page's text, ready to write out.
class OfficePage {
  const OfficePage({required this.paragraphs, required this.size});

  final List<TextParagraph> paragraphs;

  /// The page's own size in points, so the document keeps its shape.
  final TextRect size;
}

/// A Word document carrying [pages]' text.
///
/// The layout is RECONSTRUCTED, not preserved. A PDF records where glyphs sit,
/// not that they form a paragraph, so what comes out is the text in reading
/// order with paragraph breaks inferred - not a copy of the page.
Uint8List writeDocx(List<OfficePage> pages) {
  final body = StringBuffer();

  for (var i = 0; i < pages.length; i++) {
    if (i != 0) {
      body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    }

    for (final paragraph in pages[i].paragraphs) {
      body.write(
        '<w:p><w:r><w:t xml:space="preserve">'
        '${escapeXml(paragraph.text)}'
        '</w:t></w:r></w:p>',
      );
    }
  }

  // Word measures in twentieths of a point. A document that keeps the page
  // size the PDF had prints on the same paper.
  final size = pages.isEmpty
      ? const TextRect(left: 0, bottom: 0, right: 595, top: 842)
      : pages.first.size;

  final document =
      '$xmlHeader'
      '<w:document xmlns:w="http://schemas.openxmlformats.org'
      '/wordprocessingml/2006/main">'
      '<w:body>$body'
      '<w:sectPr><w:pgSz w:w="${(size.width * 20).round()}" '
      'w:h="${(size.height * 20).round()}"/></w:sectPr>'
      '</w:body></w:document>';

  return writeZip([
    ZipEntry(
      name: '[Content_Types].xml',
      bytes: utf8.encode(
        '$xmlHeader'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006'
        '/content-types">'
        '<Default Extension="rels" ContentType="application/vnd'
        '.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd'
        '.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>',
      ),
    ),
    ZipEntry(
      name: '_rels/.rels',
      bytes: utf8.encode(
        packageRelationships('officeDocument', 'word/document.xml'),
      ),
    ),
    ZipEntry(name: 'word/document.xml', bytes: utf8.encode(document)),
  ]);
}
