import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/archive/pdfa_writer.dart';

import '../../../scripts/pdf_fixture_builder.dart';

/// A document with no fonts, which is what makes it convertible: Folio can
/// embed no font programs, so a document that names one cannot be archived.
Uint8List convertible({String? extraCatalogEntries, String? infoDict}) {
  final text = latin1.decode(
    buildPdf(
      generatedPages(1),
      omitText: true,
      extraCatalogEntries: extraCatalogEntries,
      infoDict: infoDict,
    ),
    allowInvalid: true,
  );

  return Uint8List.fromList(latin1.encode(text));
}

String archived({String? extraCatalogEntries, String? infoDict}) =>
    latin1.decode(
      writePdfaDocument(
        convertible(
          extraCatalogEntries: extraCatalogEntries,
          infoDict: infoDict,
        ),
        at: DateTime.utc(2026, 8, 28, 10, 30),
      ),
      allowInvalid: true,
    );

String objectBody(String out, int number) => RegExp(
  '(?<![0-9])$number 0 obj(.*?)endobj',
  dotAll: true,
).allMatches(out).last.group(1)!;

void main() {
  test('a document naming a font it does not carry is refused', () {
    expect(
      () => writePdfaDocument(Uint8List.fromList(buildPdf(generatedPages(1)))),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  // The refusal has to say WHICH font, or the user has nothing to act on.
  test('the refusal names what is in the way', () {
    try {
      writePdfaDocument(Uint8List.fromList(buildPdf(generatedPages(1))));
      fail('expected a refusal');
    } on UnsupportedPdfStructure catch (f) {
      expect(f.technicalDetail, contains('Helvetica'));
    }
  });

  test('the file declares the version PDF/A-2 is defined against', () {
    expect(archived().startsWith('%PDF-1.7'), isTrue);
  });

  // Not decoration: it is how a transfer program tells the file is binary and
  // stops rewriting its line endings.
  test('the header carries the binary marker', () {
    final bytes = writePdfaDocument(convertible());

    expect(bytes.sublist(10, 14).every((b) => b > 127), isTrue);
  });

  test('the catalogue points at an output intent', () {
    final out = archived();
    final catalogue = objectBody(out, 1);

    expect(catalogue, contains('/OutputIntents ['));

    final intent = RegExp(
      r'/OutputIntents \[(\d+) 0 R\]',
    ).firstMatch(catalogue)!.group(1)!;

    expect(objectBody(out, int.parse(intent)), contains('/S /GTS_PDFA1'));
  });

  test('the output intent carries the profile, not a name for one', () {
    final out = archived();
    final intent = RegExp(
      r'/OutputIntents \[(\d+) 0 R\]',
    ).firstMatch(objectBody(out, 1))!.group(1)!;

    final profile = RegExp(
      r'/DestOutputProfile (\d+) 0 R',
    ).firstMatch(objectBody(out, int.parse(intent)))!.group(1)!;

    final icc = objectBody(out, int.parse(profile));

    expect(icc, contains('/N 3'));
    // 'acsp' is the ICC file signature. Its absence means the stream holds
    // something that is not a profile.
    expect(icc, contains('acsp'));
  });

  test('the catalogue points at an XMP packet', () {
    final out = archived();
    final metadata = RegExp(
      r'/Metadata (\d+) 0 R',
    ).firstMatch(objectBody(out, 1))!.group(1)!;

    final packet = objectBody(out, int.parse(metadata));

    expect(packet, contains('/Type /Metadata'));
    expect(packet, contains('/Subtype /XML'));
    expect(packet, contains('<pdfaid:part>2</pdfaid:part>'));
    expect(packet, contains('<pdfaid:conformance>B</pdfaid:conformance>'));
  });

  // A reader that can find the packet must be able to read it without running
  // a filter, so this one stream stays uncompressed.
  test('the metadata packet is not compressed', () {
    final out = archived();
    final metadata = RegExp(
      r'/Metadata (\d+) 0 R',
    ).firstMatch(objectBody(out, 1))!.group(1)!;

    expect(objectBody(out, int.parse(metadata)), isNot(contains('/Filter')));
  });

  // A validator compares the packet against /Info field by field. A title in
  // one and not the other fails the document.
  test('the packet carries the same title the document does', () {
    final out = archived(infoDict: '<< /Title (Annual Report) >>');

    expect(out, contains('Annual Report</rdf:li>'));
  });

  test('a title with an ampersand does not break the packet', () {
    final out = archived(infoDict: r'<< /Title (Smith \& Co) >>');

    expect(out, contains('Smith &amp; Co'));
    expect(out, isNot(contains('Smith & Co</rdf:li>')));
  });

  test('the trailer carries a document identifier', () {
    expect(archived(), contains('/ID ['));
  });

  test('the pages survive', () {
    final out = archived();

    expect(out, contains('/Type /Page'));
    expect(out, contains('/MediaBox'));
  });

  group('what conversion takes out', () {
    test('embedded JavaScript is gone', () {
      final out = archived(extraCatalogEntries: kJavaScriptNames);

      expect(out, isNot(contains('/JavaScript')));
      expect(out, isNot(contains('app.alert')));
    });

    // The catalogue MENTIONS the JavaScript; it is not itself a script. An
    // earlier version dropped any object matching the word and deleted the
    // document's root - which passes every test that only asks for an
    // absence, because everything is absent from a document with no root.
    test('the document still has a root afterwards', () {
      final out = archived(extraCatalogEntries: kJavaScriptNames);

      expect(out, contains('/Type /Catalog'));
      expect(out, contains('/Type /Page'));
      expect(out, contains('/OutputIntents'));
    });

    test('a script in its own object is dropped, and only it', () {
      final source = latin1
          .decode(convertible(), allowInvalid: true)
          .replaceFirst('/Type /Catalog', '/Type /Catalog /OpenAction 40 0 R')
          .replaceFirst(
            'xref',
            '40 0 obj\n<< /Type /Action /S /JavaScript /JS (app.alert\\(1\\);) '
                '>>\nendobj\n41 0 obj\n<< /Type /Anything /Keep (me) '
                '>>\nendobj\nxref',
          );

      final out = latin1.decode(
        writePdfaDocument(Uint8List.fromList(latin1.encode(source))),
        allowInvalid: true,
      );

      expect(out, isNot(contains('app.alert')));
      expect(out, contains('/Keep (me)'));
      expect(out, contains('/Type /Catalog'));
    });

    // An action that runs on opening is a script whether or not it is in the
    // name tree.
    test('an inline open action is removed', () {
      final source = latin1
          .decode(convertible(), allowInvalid: true)
          .replaceFirst(
            '/Type /Catalog',
            '/Type /Catalog /OpenAction << /S /JavaScript /JS (evil) >>',
          );

      final out = latin1.decode(
        writePdfaDocument(Uint8List.fromList(latin1.encode(source))),
        allowInvalid: true,
      );

      expect(out, isNot(contains('/OpenAction')));
      expect(out, isNot(contains('(evil)')));
      expect(out, contains('/Type /Catalog'));
    });

    test('an attached file in its own object is dropped', () {
      final source = latin1
          .decode(convertible(), allowInvalid: true)
          .replaceFirst(
            'xref',
            '40 0 obj\n<< /Type /Filespec /F (notes.txt) >>\nendobj\nxref',
          );

      final out = latin1.decode(
        writePdfaDocument(Uint8List.fromList(latin1.encode(source))),
        allowInvalid: true,
      );

      expect(out, isNot(contains('notes.txt')));
      expect(out, contains('/Type /Catalog'));
    });

    // An action that runs on a page event is a script too, and it lives in
    // /AA rather than in the name tree.
    test('additional actions are removed', () {
      final source = latin1
          .decode(convertible(), allowInvalid: true)
          .replaceFirst(
            '/Type /Catalog',
            '/Type /Catalog /AA << /WC << /S /JavaScript /JS (onclose) >> >>',
          );

      final out = latin1.decode(
        writePdfaDocument(Uint8List.fromList(latin1.encode(source))),
        allowInvalid: true,
      );

      expect(out, isNot(contains('/AA')));
      expect(out, isNot(contains('onclose')));
      expect(out, contains('/Type /Catalog'));
    });

    test('an attached file is gone', () {
      final out = archived(
        extraCatalogEntries:
            ' /Names << /EmbeddedFiles << /Names [(a) '
            '<< /Type /Filespec /F (notes.txt) >>] >> >>',
      );

      expect(out, isNot(contains('/EmbeddedFiles')));
      expect(out, isNot(contains('notes.txt')));
    });

    test('/NeedAppearances is turned off rather than left true', () {
      final out = archived(
        extraCatalogEntries: ' /AcroForm << /NeedAppearances true >>',
      );

      expect(out, contains('/NeedAppearances false'));
      expect(out, isNot(contains('/NeedAppearances true')));
    });
  });

  // The whole point of a full rewrite: an archival file is one document, not
  // a document plus every revision it passed through.
  group('a document that has been updated in place', () {
    /// The fixture with object 1 redefined by an appended revision, the way
    /// every incremental writer in Folio leaves a document.
    Uint8List updated() {
      final base = latin1.decode(convertible(), allowInvalid: true);
      final catalogue = RegExp(
        r'(?<![0-9])1 0 obj(.*?)endobj',
        dotAll: true,
      ).firstMatch(base)!.group(1)!;

      return Uint8List.fromList(
        latin1.encode(
          '$base'
          '1 0 obj${catalogue.replaceFirst('/Type /Catalog', '/Type /Catalog /Updated true')}endobj\n'
          'xref\n1 1\n0000000000 00000 n \n'
          'trailer\n<< /Size 12 /Root 1 0 R /Prev 9 >>\n'
          'startxref\n9\n%%EOF\n',
        ),
      );
    }

    test('is written out once, not once per revision', () {
      final text = latin1.decode(
        writePdfaDocument(updated()),
        allowInvalid: true,
      );

      expect('%%EOF'.allMatches(text).length, 1);
      expect(RegExp(r'(?<![0-9])1 0 obj').allMatches(text).length, 1);
    });

    // And the one that survives is the LATEST, not the superseded one.
    test('keeps the revision that was current', () {
      final text = latin1.decode(
        writePdfaDocument(updated()),
        allowInvalid: true,
      );

      expect(text, contains('/Updated true'));
    });
  });

  test('converting twice gives the same bytes', () {
    expect(
      writePdfaDocument(convertible(), at: DateTime.utc(2026)),
      writePdfaDocument(convertible(), at: DateTime.utc(2026)),
    );
  });
}
