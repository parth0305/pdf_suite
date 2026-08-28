import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/office/docx_writer.dart';
import 'package:folio/domain/office/ooxml.dart';
import 'package:folio/domain/office/pptx_writer.dart';
import 'package:folio/domain/office/text_structure.dart';
import 'package:folio/domain/office/xlsx_writer.dart';

const _a4 = TextRect(left: 0, bottom: 0, right: 595, top: 842);

TextLine line(String text) => TextLine(
  words: [
    for (final word in text.split(' '))
      TextWord(
        text: word,
        bounds: const TextRect(left: 0, right: 10, bottom: 0, top: 10),
      ),
  ],
  bounds: const TextRect(left: 0, right: 100, bottom: 0, top: 10),
);

OfficePage pageOf(List<String> paragraphs) => OfficePage(
  paragraphs: [
    for (final text in paragraphs) TextParagraph([line(text)]),
  ],
  size: _a4,
);

/// The archive's files, read back through Python - an implementation nobody
/// here wrote, and the same one Word and Excel would have to agree with.
///
/// Returns null when there is no Python, so the caller can say the check was
/// skipped rather than let it pass quietly.
Future<Map<String, String>?> unzip(Uint8List bytes, List<String> names) async {
  String? python;
  for (final name in ['python3', 'python']) {
    try {
      if ((await Process.run(name, ['--version'])).exitCode == 0) {
        python = name;
        break;
      }
    } on ProcessException {
      continue;
    }
  }
  if (python == null) return null;

  final dir = await Directory.systemTemp.createTemp('office');
  try {
    final path = '${dir.path}/probe.zip';
    await File(path).writeAsBytes(bytes);

    // Base64 on the way out: the parts are UTF-8 and the Windows console is
    // not, and a check that fails on how it reports itself says nothing about
    // what it was checking.
    final result = await Process.run(python, [
      '-c',
      'import zipfile,sys,base64\n'
          'z=zipfile.ZipFile(sys.argv[1])\n'
          'assert z.testzip() is None\n'
          'print("names:"+",".join(sorted(z.namelist())))\n'
          'for n in sys.argv[2:]:\n'
          '    print(n+":"+base64.b64encode(z.read(n)).decode())',
      path,
      ...names,
    ]);

    if (result.exitCode != 0) throw StateError(result.stderr.toString());

    final out = <String, String>{};
    for (final row in (result.stdout as String).trim().split('\n')) {
      final at = row.indexOf(':');
      final key = row.substring(0, at);
      final value = row.substring(at + 1).trim();
      out[key] = key == 'names' ? value : utf8.decode(base64.decode(value));
    }
    return out;
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  group('escaping', () {
    test('the characters XML reserves are escaped', () {
      expect(escapeXml('a & b < c > d'), 'a &amp; b &lt; c &gt; d');
    });

    // A PDF's text layer can carry control characters. They are not permitted
    // in XML at all, and Word refuses the whole file rather than the
    // paragraph.
    test('a control character is dropped', () {
      expect(escapeXml('ab'), 'ab');
    });

    test('tabs and newlines survive', () {
      expect(escapeXml('a\tb\nc'), 'a\tb\nc');
    });

    test('text outside Latin-1 is left alone', () {
      expect(escapeXml('₹ नमस'), '₹ नमस');
    });
  });

  group('column names', () {
    // Spreadsheet columns are not base 26: there is no zero digit.
    test('count the way a spreadsheet does', () {
      expect(columnName(1), 'A');
      expect(columnName(26), 'Z');
      expect(columnName(27), 'AA');
      expect(columnName(28), 'AB');
      expect(columnName(52), 'AZ');
      expect(columnName(53), 'BA');
      expect(columnName(702), 'ZZ');
      expect(columnName(703), 'AAA');
    });
  });

  group('docx', () {
    test('the parts a reader looks for are all there', () async {
      final files = await unzip(
        writeDocx([
          pageOf(['Hello']),
        ]),
        ['word/document.xml', '_rels/.rels'],
      );
      if (files == null) {
        markTestSkipped('no Python on this machine');
        return;
      }

      expect(
        files['names'],
        '[Content_Types].xml,_rels/.rels,word/document.xml',
      );
      expect(files['_rels/.rels'], contains('word/document.xml'));
    });

    test('the text is in the document', () async {
      final files = await unzip(
        writeDocx([
          pageOf(['Hello Priya']),
        ]),
        ['word/document.xml'],
      );
      if (files == null) return;

      expect(
        files['word/document.xml'],
        contains('<w:t xml:space="preserve">Hello Priya</w:t>'),
      );
    });

    test('each paragraph is a paragraph', () async {
      final files = await unzip(
        writeDocx([
          pageOf(['One', 'Two']),
        ]),
        ['word/document.xml'],
      );
      if (files == null) return;

      expect('<w:p>'.allMatches(files['word/document.xml']!).length, 2);
    });

    // Otherwise a hundred-page document arrives as one endless page.
    test('pages are separated by a page break', () async {
      final files = await unzip(
        writeDocx([
          pageOf(['One']),
          pageOf(['Two']),
        ]),
        ['word/document.xml'],
      );
      if (files == null) return;

      expect(files['word/document.xml'], contains('w:type="page"'));
    });

    // Word measures in twentieths of a point.
    test('the page keeps the size the PDF had', () async {
      final files = await unzip(
        writeDocx([
          pageOf(['One']),
        ]),
        ['word/document.xml'],
      );
      if (files == null) return;

      expect(files['word/document.xml'], contains('w:w="11900"'));
      expect(files['word/document.xml'], contains('w:h="16840"'));
    });

    test('an ampersand in the text does not break the part', () async {
      final files = await unzip(
        writeDocx([
          pageOf(['Smith & Co']),
        ]),
        ['word/document.xml'],
      );
      if (files == null) return;

      expect(files['word/document.xml'], contains('Smith &amp; Co'));
    });

    test('a document with no pages is still a document', () async {
      final files = await unzip(writeDocx([]), ['word/document.xml']);
      if (files == null) return;

      expect(files['word/document.xml'], contains('<w:body>'));
    });
  });

  group('xlsx', () {
    test('the parts a reader looks for are all there', () async {
      final files = await unzip(
        writeXlsx([
          const OfficeSheet(
            name: 'Page 1',
            rows: [
              ['Item', 'Amount'],
            ],
          ),
        ]),
        ['xl/workbook.xml', 'xl/worksheets/sheet1.xml'],
      );
      if (files == null) {
        markTestSkipped('no Python on this machine');
        return;
      }

      expect(
        files['names'],
        '[Content_Types].xml,_rels/.rels,xl/_rels/workbook.xml.rels,'
        'xl/workbook.xml,xl/worksheets/sheet1.xml',
      );
    });

    test('cells land in the columns they were given', () async {
      final files = await unzip(
        writeXlsx([
          const OfficeSheet(
            name: 'S',
            rows: [
              ['Item', 'Amount'],
              ['Paper', '480'],
            ],
          ),
        ]),
        ['xl/worksheets/sheet1.xml'],
      );
      if (files == null) return;

      final sheet = files['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('r="A1"'));
      expect(sheet, contains('r="B1"'));
      expect(sheet, contains('r="A2"'));
      expect(sheet, contains('<t xml:space="preserve">Amount</t>'));
    });

    // Inline strings, so there is no shared-string table to keep consistent
    // with the sheets that would reference it.
    test('strings are stored in the cell', () async {
      final files = await unzip(
        writeXlsx([
          const OfficeSheet(
            name: 'S',
            rows: [
              ['Text'],
            ],
          ),
        ]),
        ['xl/worksheets/sheet1.xml'],
      );
      if (files == null) return;

      expect(files['xl/worksheets/sheet1.xml'], contains('t="inlineStr"'));
    });

    test('several sheets each get their own part', () async {
      final files = await unzip(
        writeXlsx([
          const OfficeSheet(
            name: 'One',
            rows: [
              ['a'],
            ],
          ),
          const OfficeSheet(
            name: 'Two',
            rows: [
              ['b'],
            ],
          ),
        ]),
        ['xl/workbook.xml'],
      );
      if (files == null) return;

      expect(files['names'], contains('xl/worksheets/sheet2.xml'));
      expect(files['xl/workbook.xml'], contains('name="One"'));
      expect(files['xl/workbook.xml'], contains('name="Two"'));
    });

    // A name Excel rejects makes the whole workbook unopenable, which is a
    // poor trade for a page title.
    test('a sheet name Excel would reject is cleaned up', () async {
      final files = await unzip(
        writeXlsx([
          const OfficeSheet(
            name: 'Report [2026]/Q1',
            rows: [
              ['a'],
            ],
          ),
        ]),
        ['xl/workbook.xml'],
      );
      if (files == null) return;

      expect(files['xl/workbook.xml'], isNot(contains('[')));
      expect(files['xl/workbook.xml'], isNot(contains('/Q1')));
    });

    test('a very long sheet name is cut to what Excel allows', () async {
      final files = await unzip(
        writeXlsx([
          OfficeSheet(
            name: 'x' * 60,
            rows: const [
              ['a'],
            ],
          ),
        ]),
        ['xl/workbook.xml'],
      );
      if (files == null) return;

      final name = RegExp(
        r'name="(x+)"',
      ).firstMatch(files['xl/workbook.xml']!)!.group(1)!;
      expect(name.length, 31);
    });
  });

  group('pptx', () {
    test('every part a presentation needs is there', () async {
      final files = await unzip(
        writePptx([
          pageOf(['Hello']),
        ]),
        ['ppt/presentation.xml', 'ppt/slides/slide1.xml'],
      );
      if (files == null) {
        markTestSkipped('no Python on this machine');
        return;
      }

      for (final part in [
        '[Content_Types].xml',
        '_rels/.rels',
        'ppt/presentation.xml',
        'ppt/_rels/presentation.xml.rels',
        'ppt/slideMasters/slideMaster1.xml',
        'ppt/slideMasters/_rels/slideMaster1.xml.rels',
        'ppt/slideLayouts/slideLayout1.xml',
        'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
        'ppt/theme/theme1.xml',
        'ppt/slides/slide1.xml',
        'ppt/slides/_rels/slide1.xml.rels',
      ]) {
        expect(files['names'], contains(part), reason: part);
      }
    });

    test('the text is on the slide', () async {
      final files = await unzip(
        writePptx([
          pageOf(['Hello Priya']),
        ]),
        ['ppt/slides/slide1.xml'],
      );
      if (files == null) return;

      expect(
        files['ppt/slides/slide1.xml'],
        contains('<a:t>Hello Priya</a:t>'),
      );
    });

    test('one slide per page', () async {
      final files = await unzip(
        writePptx([
          pageOf(['One']),
          pageOf(['Two']),
          pageOf(['Three']),
        ]),
        ['ppt/presentation.xml'],
      );
      if (files == null) return;

      expect(files['names'], contains('ppt/slides/slide3.xml'));
      expect('<p:sldId '.allMatches(files['ppt/presentation.xml']!).length, 3);
    });

    // Identifiers below 256 are reserved, and a presentation using one is
    // rejected rather than repaired.
    test('slide identifiers start above the reserved range', () async {
      final files = await unzip(
        writePptx([
          pageOf(['One']),
        ]),
        ['ppt/presentation.xml'],
      );
      if (files == null) return;

      expect(files['ppt/presentation.xml'], contains('id="256"'));
    });

    // PowerPoint measures in 914400ths of an inch.
    test('the slide is the size the page was', () async {
      final files = await unzip(
        writePptx([
          pageOf(['One']),
        ]),
        ['ppt/presentation.xml'],
      );
      if (files == null) return;

      // On the slide size specifically: the notes size carries the same two
      // attributes, so an assertion that only looks for the numbers passes
      // while the slides themselves are the wrong size.
      expect(
        files['ppt/presentation.xml'],
        contains('<p:sldSz cx="${595 * 12700}" cy="${842 * 12700}"/>'),
      );
    });

    // A shape with no paragraph at all is reported as damaged rather than
    // empty.
    test('a page with no text still makes a valid slide', () async {
      final files = await unzip(writePptx([pageOf([])]), [
        'ppt/slides/slide1.xml',
      ]);
      if (files == null) return;

      expect(files['ppt/slides/slide1.xml'], contains('<a:p/>'));
    });
  });
}
