import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/archive/icc_profile.dart';
import 'package:folio/domain/archive/pdfa_check.dart';
import 'package:folio/domain/archive/xmp_packet.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

/// The conformance level Folio writes.
///
/// Part 2, level B. Part 1 forbids transparency, which rules out every
/// document carrying a signature or an image watermark; level A additionally
/// requires a tagged structure tree that Folio has no way to infer from a
/// scanned page. Level B is what "this will still open in fifty years" means
/// in practice.
const pdfaPart = 2;
const pdfaConformance = 'B';

/// Rewrites [pdf] as PDF/A-2b.
///
/// A FULL rewrite rather than an incremental update. An archival document that
/// is the last link in a chain of appended revisions still carries every
/// superseded object; and PDF/A wants one coherent file, not a history.
///
/// Throws [UnsupportedPdfStructure] when [checkPdfa] found something that
/// cannot be repaired. Stamping a file as PDF/A that is not is worse than
/// refusing, because the stamp is exactly what an archive trusts.
Uint8List writePdfaDocument(Uint8List pdf, {DateTime? at}) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final report = checkPdfa(text);

  if (!report.canConvert) {
    throw UnsupportedPdfStructure(
      technicalDetail: report.blockers.entries
          .map((e) => '${e.key.name}: ${e.value.join(', ')}')
          .join('; '),
    );
  }

  final objects = parsePdfObjects(pdf);
  if (objects.isEmpty) {
    throw const UnsupportedPdfStructure(technicalDetail: 'no objects');
  }

  final roots = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  if (roots.isEmpty) {
    throw const UnsupportedPdfStructure(technicalDetail: 'no /Root');
  }
  final catalogNumber = int.parse(roots.last.group(1)!);

  // Last definition wins, as everywhere else: an incremental update supersedes
  // what came before it, and rewriting a stale catalogue would drop every page
  // added since.
  final latest = <int, PdfObject>{};
  for (final object in objects) {
    latest[object.number] = object;
  }

  var next = latest.keys.reduce((a, b) => a > b ? a : b) + 1;
  final iccNumber = next++;
  final intentNumber = next++;
  final metadataNumber = next++;

  final icc = buildSrgbIccProfile();
  final metadata = PdfMetadata.readFrom(pdf);

  final out = <PdfObject>[];

  for (final object in latest.values) {
    var body = latin1.decode(object.body, allowInvalid: true);

    if (object.number == catalogNumber) {
      body = _archivalCatalogue(body, intentNumber, metadataNumber);
    }
    // Not an `else`: /AcroForm usually sits IN the catalogue, which is
    // precisely the object the branch above already claimed.
    if (report.removals.contains(PdfaIssue.needAppearances)) {
      body = body.replaceAll(
        RegExp(r'/NeedAppearances\s+true'),
        '/NeedAppearances false',
      );
    }

    out.add(
      PdfObject(
        number: object.number,
        generation: object.generation,
        body: latin1.encode(body),
      ),
    );
  }

  out
    ..add(
      PdfObject(
        number: iccNumber,
        generation: 0,
        body: [
          ...latin1.encode('<< /N 3 /Length ${icc.length} >>\nstream\n'),
          ...icc,
          ...latin1.encode('\nendstream'),
        ],
      ),
    )
    ..add(
      PdfObject(
        number: intentNumber,
        generation: 0,
        body: latin1.encode(
          '<< /Type /OutputIntent /S /GTS_PDFA1 '
          '/OutputConditionIdentifier (sRGB IEC61966-2.1) '
          '/Info (sRGB IEC61966-2.1) '
          '/DestOutputProfile $iccNumber 0 R >>',
        ),
      ),
    );

  // UTF-8, not Latin-1: the packet opens with a byte-order mark, and its
  // fields carry whatever the document's title is written in.
  final packet = utf8.encode(
    buildXmpPacket(
      part: pdfaPart,
      conformance: pdfaConformance,
      metadata: metadata,
      producer: 'Folio',
      at: at,
    ),
  );

  out.add(
    PdfObject(
      number: metadataNumber,
      generation: 0,
      body: [
        // The metadata stream is NOT compressed: PDF/A requires that a reader
        // able to find the packet can read it without a filter.
        ...latin1.encode(
          '<< /Type /Metadata /Subtype /XML /Length ${packet.length} '
          '>>\nstream\n',
        ),
        ...packet,
        ...latin1.encode('\nendstream'),
      ],
    ),
  );

  return _withoutRemovals(pdf, out, report);
}

/// The catalogue with an output intent and a metadata stream.
///
/// `/OutputIntents` is an ARRAY. A document may already declare one - for a
/// press condition, say - and replacing it would change what the colours in it
/// mean.
String _archivalCatalogue(String body, int intent, int metadata) {
  var out = body;

  final existing = RegExp(r'/OutputIntents\s*\[([^\]]*)\]').firstMatch(out);
  out = existing == null
      ? _insert(out, '/OutputIntents [$intent 0 R]')
      : out.replaceRange(
          existing.start,
          existing.end,
          '/OutputIntents [${existing.group(1)!.trim()} $intent 0 R]',
        );

  final oldMetadata = RegExp(r'/Metadata\s+\d+\s+\d+\s+R').firstMatch(out);
  out = oldMetadata == null
      ? _insert(out, '/Metadata $metadata 0 R')
      : out.replaceRange(
          oldMetadata.start,
          oldMetadata.end,
          '/Metadata $metadata 0 R',
        );

  return out;
}

/// Inserts [entry] just after the dictionary's opening `<<`, which needs no
/// index arithmetic - the approach every writer here settled on after getting
/// the closing brace wrong.
String _insert(String body, String entry) {
  final open = body.indexOf('<<');
  return open == -1 ? body : body.replaceRange(open + 2, open + 2, ' $entry');
}

/// The document written out, with the disallowed pieces taken out on the way.
Uint8List _withoutRemovals(
  Uint8List original,
  List<PdfObject> objects,
  PdfaReport report,
) {
  final kept = <PdfObject>[];

  for (final object in objects) {
    final body = latin1.decode(object.body, allowInvalid: true);

    // An object that IS a JavaScript action, or IS an attached file, is
    // dropped whole: what remains of a /Filespec with its file taken out is a
    // broken reference, and PDF/A has no more time for that than for the file.
    //
    // "Is one" and "mentions one" are different questions. A catalogue with an
    // inline /Names /JavaScript tree mentions one, and dropping THAT deletes
    // the document's root - which still passes a test that only asks whether
    // the word JavaScript is gone.
    if (report.removals.contains(PdfaIssue.javaScript) &&
        _isJavaScriptAction(body)) {
      continue;
    }
    if (report.removals.contains(PdfaIssue.embeddedFile) &&
        RegExp(r'/Type\s*/Filespec').hasMatch(body)) {
      continue;
    }

    kept.add(
      PdfObject(
        number: object.number,
        generation: object.generation,
        body: latin1.encode(_withoutNames(body, report)),
      ),
    );
  }

  // PDF/A-2 is defined against PDF 1.7. A file that declares 1.4 and uses
  // anything from later is inconsistent, and a validator says so.
  return writePdfDocument(original, kept, version: '1.7');
}

/// An object that is itself a JavaScript action, rather than one that merely
/// contains the word somewhere inside it.
bool _isJavaScriptAction(String body) {
  final open = body.indexOf('<<');
  if (open < 0) return false;

  // Top level only: an action nested inside this object belongs to whatever
  // is around it, and dropping the whole object takes that with it.
  final top = body.substring(open, _matchingClose(body, open));
  return RegExp(r'/S\s*/JavaScript').hasMatch(_withoutNested(top));
}

/// The dictionary with everything nested inside it blanked out.
String _withoutNested(String dict) {
  final out = StringBuffer();
  var depth = 0;

  for (var i = 0; i < dict.length; i++) {
    if (dict.startsWith('<<', i)) {
      depth++;
      i++;
      continue;
    }
    if (dict.startsWith('>>', i)) {
      depth--;
      i++;
      continue;
    }
    if (depth <= 1) out.write(dict[i]);
  }

  return out.toString();
}

int _matchingClose(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length - 1; i++) {
    if (text.startsWith('<<', i)) {
      depth++;
      i++;
    } else if (text.startsWith('>>', i)) {
      depth--;
      if (depth == 0) return i + 2;
      i++;
    }
  }
  return text.length;
}

/// The entries that pointed at what was just removed, and the actions PDF/A
/// does not allow at all.
String _withoutNames(String body, PdfaReport report) {
  var out = body;

  if (report.removals.contains(PdfaIssue.javaScript)) {
    out = _dropNameTree(out, 'JavaScript');
    // An action that runs when the document opens, and the additional-actions
    // dictionary that runs one on every page event.
    out = _dropNameTree(out, 'OpenAction');
    out = _dropNameTree(out, 'AA');
  }
  if (report.removals.contains(PdfaIssue.embeddedFile)) {
    out = _dropNameTree(out, 'EmbeddedFiles');
  }

  return out;
}

String _dropNameTree(String body, String name) {
  final at = RegExp(
    '/$name'
    r'\s*<<',
  ).firstMatch(body);
  if (at == null) return body;

  var depth = 0;
  for (var i = at.end - 2; i < body.length - 1; i++) {
    if (body.startsWith('<<', i)) {
      depth++;
      i++;
    } else if (body.startsWith('>>', i)) {
      depth--;
      if (depth == 0) return body.replaceRange(at.start, i + 2, '');
      i++;
    }
  }

  return body;
}
