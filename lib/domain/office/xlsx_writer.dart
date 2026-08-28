import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/domain/office/ooxml.dart';
import 'package:folio/domain/office/zip_writer.dart';

/// One sheet: a name and its rows of cells.
class OfficeSheet {
  const OfficeSheet({required this.name, required this.rows});

  final String name;
  final List<List<String>> rows;
}

/// A workbook carrying [sheets].
///
/// A spreadsheet only makes sense for a document that is a table, and a PDF
/// has no notion of a cell - the columns are inferred from how far apart the
/// words are. On a document that is not a table the result is one column of
/// lines, which is honest but not useful, and the app says so.
Uint8List writeXlsx(List<OfficeSheet> sheets) {
  final parts = <ZipEntry>[];
  final workbookSheets = StringBuffer();
  final workbookRels = StringBuffer();
  final overrides = StringBuffer();

  for (var i = 0; i < sheets.length; i++) {
    final id = i + 1;
    final sheet = sheets[i];

    workbookSheets.write(
      '<sheet name="${escapeXml(_sheetName(sheet.name))}" '
      'sheetId="$id" r:id="rId$id"/>',
    );
    workbookRels.write(
      '<Relationship Id="rId$id" Type="http://schemas.openxmlformats.org'
      '/officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet$id.xml"/>',
    );
    overrides.write(
      '<Override PartName="/xl/worksheets/sheet$id.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument'
      '.spreadsheetml.worksheet+xml"/>',
    );

    final data = StringBuffer();
    for (var r = 0; r < sheet.rows.length; r++) {
      data.write('<row r="${r + 1}">');
      for (var c = 0; c < sheet.rows[r].length; c++) {
        // Inline strings, so the workbook needs no shared-string table. One
        // fewer part to keep consistent with the sheets that reference it.
        data.write(
          '<c r="${columnName(c + 1)}${r + 1}" t="inlineStr"><is><t '
          'xml:space="preserve">${escapeXml(sheet.rows[r][c])}</t></is></c>',
        );
      }
      data.write('</row>');
    }

    parts.add(
      ZipEntry(
        name: 'xl/worksheets/sheet$id.xml',
        bytes: utf8.encode(
          '$xmlHeader'
          '<worksheet xmlns="http://schemas.openxmlformats.org'
          '/spreadsheetml/2006/main"><sheetData>$data</sheetData></worksheet>',
        ),
      ),
    );
  }

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
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd'
        '.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '$overrides</Types>',
      ),
    ),
    ZipEntry(
      name: '_rels/.rels',
      bytes: utf8.encode(
        packageRelationships('officeDocument', 'xl/workbook.xml'),
      ),
    ),
    ZipEntry(
      name: 'xl/workbook.xml',
      bytes: utf8.encode(
        '$xmlHeader'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml'
        '/2006/main" xmlns:r="http://schemas.openxmlformats.org'
        '/officeDocument/2006/relationships">'
        '<sheets>$workbookSheets</sheets></workbook>',
      ),
    ),
    ZipEntry(
      name: 'xl/_rels/workbook.xml.rels',
      bytes: utf8.encode(
        '$xmlHeader'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006'
        '/relationships">$workbookRels</Relationships>',
      ),
    ),
    ...parts,
  ]);
}

/// A sheet name Excel will accept.
///
/// Thirty-one characters, and none of `[]:*?/\`. A name Excel rejects makes
/// the whole workbook unopenable, which is a poor trade for a page title.
String _sheetName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final safe = cleaned.isEmpty ? 'Sheet' : cleaned;

  return safe.length <= 31 ? safe : safe.substring(0, 31);
}
