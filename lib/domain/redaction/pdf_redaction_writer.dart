import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfStreamBody;
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/stamp_appearance.dart'
    show helveticaFontObject;
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';
import 'package:folio/domain/redaction/pdf_image_object.dart';

/// Everything a redacted page needs: the pixels that replace it, and the text
/// that survived.
class RedactedPage {
  const RedactedPage({
    required this.widthPx,
    required this.heightPx,
    required this.rgb,
    required this.invisibleText,
  });

  final int widthPx;
  final int heightPx;

  /// RGB samples, boxes already painted in.
  final List<int> rgb;

  /// A content stream fragment in text render mode 3.
  final String invisibleText;
}

/// Rewrites [original] with each page in [pages] replaced by its raster.
///
/// A **full rewrite**, never an incremental update. An incremental update
/// appends, so the original content stream would still sit at the front of the
/// output where any text editor finds it. Redaction that leaves the bytes in
/// the file is not redaction, and this is the reason the slice waited for the
/// object layer.
Uint8List writeRedacted({
  required List<int> original,
  required Map<int, RedactedPage> pages,
}) {
  if (pages.isEmpty) {
    throw ArgumentError.value(pages, 'pages', 'nothing to redact');
  }

  final text = latin1.decode(original, allowInvalid: true);
  final reader = PdfObjectReader.parse(text);
  final objects = parsePdfObjects(original);

  final pageObjects = <int, PdfPageObject>{};
  for (final index in pages.keys) {
    final page = reader.pageAt(index);
    if (page == null) {
      throw ArgumentError.value(index, 'pages', 'no such page');
    }
    pageObjects[index] = page;
  }

  // What each redacted page draws, and what it draws it with.
  final droppedContents = <int>{};
  final candidateResources = <int>{};
  for (final page in pageObjects.values) {
    droppedContents.addAll(_contentRefs(page.rawDictionary));
    candidateResources.addAll(_xObjectRefs(page.rawDictionary));
  }

  _refuseSharedContent(reader, pageObjects.keys.toSet(), droppedContents);

  var next = objects.map((o) => o.number).reduce((a, b) => a > b ? a : b) + 1;
  final fontNumber = next++;

  final replacements = <int, List<int>>{};
  final additions = <PdfObject>[];

  for (final entry in pageObjects.entries) {
    final page = entry.value;
    final data = pages[entry.key]!;

    final image = imageXObject(
      widthPx: data.widthPx,
      heightPx: data.heightPx,
      rgb: data.rgb,
    );
    final imageNumber = next++;
    additions.add(
      PdfObject(
        number: imageNumber,
        generation: 0,
        body: [
          ...latin1.encode('${image.dict}\nstream\n'),
          ...image.samples,
          ...latin1.encode('\nendstream'),
        ],
      ),
    );

    final mediaBox = _mediaBoxArray(text, page.rawDictionary);
    final content =
        'q\n${mediaBox.width} 0 0 ${mediaBox.height} '
        '${mediaBox.x} ${mediaBox.y} cm\n/RdIm0 Do\nQ\n'
        '${data.invisibleText}';
    final body = pdfStreamBody(content);
    final contentNumber = next++;
    additions.add(
      PdfObject(
        number: contentNumber,
        generation: 0,
        body: [
          ...latin1.encode(
            '<< /Length ${body.bytes.length}${body.filter} >>\nstream\n',
          ),
          ...body.bytes,
          ...latin1.encode('\nendstream'),
        ],
      ),
    );

    replacements[page.objectNumber] = latin1.encode(
      _redactedPageDictionary(
        page.rawDictionary,
        imageNumber: imageNumber,
        contentNumber: contentNumber,
        fontNumber: fontNumber,
      ),
    );
  }

  additions.add(
    PdfObject(
      number: fontNumber,
      generation: 0,
      body: latin1.encode(helveticaFontObject()),
    ),
  );

  final kept = [
    for (final o in objects)
      if (!droppedContents.contains(o.number))
        replacements.containsKey(o.number)
            ? PdfObject(
                number: o.number,
                generation: o.generation,
                body: replacements[o.number]!,
              )
            : o,
  ];

  // An XObject the redacted pages alone referenced is a leak: an image under a
  // black box lives here, not in the content stream. One that a surviving page
  // still uses is visible in the output anyway, so removing it would break
  // that page and conceal nothing.
  final orphans = candidateResources
      .where(
        (n) => !_referencedBy(kept, additions, n, ignoring: replacements.keys),
      )
      .toSet();

  return writePdfDocument(original, [
    ...kept.where((o) => !orphans.contains(o.number)),
    ...additions,
  ]);
}

/// Object numbers named by a page's `/Contents`, direct or in an array.
Set<int> _contentRefs(String dict) {
  final match = RegExp(
    r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)',
  ).firstMatch(dict);
  if (match == null) return {};

  return RegExp(
    r'(\d+)\s+\d+\s+R',
  ).allMatches(match.group(1)!).map((m) => int.parse(m.group(1)!)).toSet();
}

/// Object numbers named inside a page's `/Resources /XObject`.
Set<int> _xObjectRefs(String dict) {
  final at = dict.indexOf('/XObject');
  if (at < 0) return {};

  final open = dict.indexOf('<<', at);
  if (open < 0) return {};
  final close = _matchingClose(dict, open);
  if (close < 0) return {};

  return RegExp(r'(\d+)\s+\d+\s+R')
      .allMatches(dict.substring(open, close))
      .map((m) => int.parse(m.group(1)!))
      .toSet();
}

int _matchingClose(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length - 1; i++) {
    if (s.startsWith('<<', i)) {
      depth++;
      i++;
    } else if (s.startsWith('>>', i)) {
      depth--;
      if (depth == 0) return i + 2;
      i++;
    }
  }
  return -1;
}

/// True when any object still names `n 0 R`, ignoring the page dictionaries
/// that are being replaced (their old text is about to disappear).
bool _referencedBy(
  List<PdfObject> kept,
  List<PdfObject> additions,
  int n, {
  required Iterable<int> ignoring,
}) {
  final pattern = RegExp('(?<!\\d)$n\\s+\\d+\\s+R');

  for (final o in [...kept, ...additions]) {
    if (ignoring.contains(o.number)) continue;
    if (pattern.hasMatch(latin1.decode(o.body, allowInvalid: true))) {
      return true;
    }
  }
  return false;
}

/// A content stream shared with a page nobody redacted has no correct answer:
/// dropping it breaks that page, keeping it leaves the redacted text in the
/// file. A partial redaction reported as success is the failure this whole
/// slice exists to prevent.
void _refuseSharedContent(
  PdfObjectReader reader,
  Set<int> redactedIndices,
  Set<int> dropped,
) {
  for (var i = 0; ; i++) {
    final page = reader.pageAt(i);
    if (page == null) break;
    if (redactedIndices.contains(i)) continue;

    if (_contentRefs(page.rawDictionary).any(dropped.contains)) {
      throw const UnsupportedPdfStructure(
        technicalDetail:
            'content stream shared with a page that was '
            'not redacted',
      );
    }
  }
}

/// The page dictionary with its content and resources REPLACED, not merged:
/// nothing the old content referenced is drawn any more.
String _redactedPageDictionary(
  String raw, {
  required int imageNumber,
  required int contentNumber,
  required int fontNumber,
}) {
  var body = raw.substring(2, raw.length - 2).trim();

  body = _removeEntry(body, '/Contents');
  body = _removeEntry(body, '/Resources');

  return '<< $body /Contents $contentNumber 0 R '
      '/Resources << /XObject << /RdIm0 $imageNumber 0 R >> '
      '/Font << /RdF1 $fontNumber 0 R >> >> >>';
}

String _removeEntry(String body, String key) {
  final at = body.indexOf(key);
  if (at < 0) return body;

  final rest = body.substring(at + key.length).trimLeft();
  final skipped = body.length - rest.length;

  if (rest.startsWith('<<')) {
    final close = _matchingClose(rest, 0);
    return body.substring(0, at) + rest.substring(close);
  }
  if (rest.startsWith('[')) {
    return body.substring(0, at) + rest.substring(rest.indexOf(']') + 1);
  }

  final ref = RegExp(r'^\d+\s+\d+\s+R').firstMatch(rest);
  if (ref != null) return body.substring(0, at) + rest.substring(ref.end);

  return body.substring(0, skipped);
}

/// The page's `/MediaBox`, falling back to the first one found in the document
/// so an inherited box still places the image correctly.
({num x, num y, num width, num height}) _mediaBoxArray(
  String document,
  String pageDict,
) {
  final pattern = RegExp(
    r'/MediaBox\s*\[\s*(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)',
  );
  final match = pattern.firstMatch(pageDict) ?? pattern.firstMatch(document);

  if (match == null) {
    // US Letter, the same fallback the rest of Folio uses.
    return (x: 0, y: 0, width: 612, height: 792);
  }

  final v = [for (var i = 1; i <= 4; i++) num.parse(match.group(i)!)];
  return (x: v[0], y: v[1], width: v[2] - v[0], height: v[3] - v[1]);
}
