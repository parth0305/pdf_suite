import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';
import 'package:folio/domain/watermark/pdf_image_watermark_writer.dart';
import 'package:folio/domain/watermark/watermark_content.dart';

/// What removing a watermark would do to a document.
class WatermarkRemoval {
  const WatermarkRemoval({
    required this.pagesAffected,
    required this.objectsDropped,
  });

  final int pagesAffected;
  final int objectsDropped;

  bool get foundAnything => pagesAffected > 0;
}

/// Finds and removes watermarks **Folio applied**.
///
/// Folio names its watermark resources `/WMF1` and `/WMGS`, which is what
/// makes them identifiable with certainty rather than by guesswork. A
/// watermark applied by any other tool carries no such marker: deciding which
/// parts of a content stream belong to it is the same problem as redaction and
/// has no reliable general answer. This refuses that case rather than
/// half-removing something and reporting success — see LIMITATIONS.
///
/// The removal is a **full rewrite**, not another incremental update.
/// Appending an update that stops drawing the watermark would leave its
/// content stream in the file, which is not removal.
({Uint8List bytes, WatermarkRemoval removal}) removeFolioWatermark(
  Uint8List pdf,
) {
  final text = latin1.decode(pdf, allowInvalid: true);

  // A watermark is applied as an incremental update, so every page it touched
  // is defined TWICE - the original and the override. Collapsing to the last
  // definition is what a reader walking the trailer chain backwards sees, and
  // carrying both through would leave stale page dictionaries in the output
  // and let their references keep objects alive that nothing needs.
  final byNumber = <int, PdfObject>{};
  for (final object in parsePdfObjects(pdf)) {
    byNumber[object.number] = object;
  }
  final objects = byNumber.values.toList();

  final rewritten = <PdfObject>[];
  var pagesAffected = 0;

  for (final object in objects) {
    final body = latin1.decode(object.body, allowInvalid: true);

    // Only page dictionaries carry the watermark's resources.
    if (!body.contains('/Type') ||
        !body.contains('/Page') ||
        body.contains('/Pages')) {
      rewritten.add(object);
      continue;
    }
    // /WMIm is the image watermark's resource name; the text mark uses
    // /WMF1 and /WMGS. All three are Folio's own.
    if (!body.contains('/$watermarkFontName') &&
        !body.contains('/$watermarkGStateName') &&
        !body.contains('/$imageWatermarkName')) {
      rewritten.add(object);
      continue;
    }

    final stripped = _withoutWatermark(body, objects);
    if (stripped == null) {
      rewritten.add(object);
      continue;
    }

    pagesAffected++;
    rewritten.add(
      PdfObject(
        number: object.number,
        generation: object.generation,
        body: latin1.encode(stripped),
      ),
    );
  }

  if (pagesAffected == 0) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'no watermark applied by Folio',
    );
  }

  // Anything the page no longer refers to - the watermark's content stream,
  // its font, its graphics state - is swept here. This is what makes the
  // removal real rather than merely invisible.
  final referenced = _referencedNumbers(
    rewritten.map((o) => latin1.decode(o.body, allowInvalid: true)).join('\n') +
        _trailerOf(text),
  );
  final kept = rewritten.where((o) => referenced.contains(o.number)).toList();

  return (
    bytes: writePdfDocument(pdf, kept),
    removal: WatermarkRemoval(
      pagesAffected: pagesAffected,
      objectsDropped: rewritten.length - kept.length,
    ),
  );
}

/// The page dictionary with the watermark's content and resources removed, or
/// null when nothing identifiable was found.
String? _withoutWatermark(String body, List<PdfObject> objects) {
  final contents = RegExp(
    r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)',
  ).firstMatch(body);
  if (contents == null) return null;

  final refs = RegExp(
    r'(\d+)\s+\d+\s+R',
  ).allMatches(contents.group(1)!).map((m) => int.parse(m.group(1)!)).toList();

  // The watermark's stream is the one that USES the watermark font, not simply
  // the last one. Position would break the moment anything else appended a
  // content stream after it.
  final watermarkRefs = refs.where((n) => _drawsWatermark(objects, n)).toSet();
  if (watermarkRefs.isEmpty) return null;

  final survivors = refs.where((n) => !watermarkRefs.contains(n)).toList();
  final merged = survivors.isEmpty
      ? '/Contents []'
      : '/Contents [${survivors.map((n) => '$n 0 R').join(' ')}]';

  var out = body.replaceRange(contents.start, contents.end, merged);
  out = _withoutResource(out, watermarkFontName);
  out = _withoutResource(out, watermarkGStateName);
  out = _withoutResource(out, imageWatermarkName);
  return out;
}

/// Whether object [number] is a content stream that draws Folio's watermark.
bool _drawsWatermark(List<PdfObject> objects, int number) {
  final object = objects.where((o) => o.number == number).lastOrNull;
  if (object == null) return false;

  final body = latin1.decode(object.body, allowInvalid: true);
  final streamAt = body.indexOf('stream');
  if (streamAt < 0) return false;

  final payload = body.contains('/FlateDecode')
      ? _inflated(object.body, body, streamAt)
      : body.substring(streamAt);

  return payload != null &&
      (payload.contains('/$watermarkFontName') ||
          payload.contains('/$imageWatermarkName'));
}

/// The stream's inflated payload, or null when it cannot be read.
String? _inflated(List<int> raw, String body, int streamAt) {
  final length = RegExp(r'/Length\s+(\d+)').firstMatch(body);
  if (length == null) return null;

  final start = body.indexOf('\n', streamAt) + 1;
  final end = start + int.parse(length.group(1)!);
  if (start <= 0 || end > raw.length) return null;

  try {
    return latin1.decode(
      ZLibCodec().decode(raw.sublist(start, end)),
      allowInvalid: true,
    );
  } on FormatException {
    return null;
  }
}

/// Removes `/Name n 0 R` from wherever it appears in a resources dictionary.
String _withoutResource(String body, String name) =>
    body.replaceAll(RegExp('/$name\\s+\\d+\\s+\\d+\\s+R\\s*'), '');

Set<int> _referencedNumbers(String text) => {
  for (final m in RegExp(r'(\d+)\s+\d+\s+R').allMatches(text))
    int.parse(m.group(1)!),
  for (final m in RegExp(r'/Root\s+(\d+)').allMatches(text))
    int.parse(m.group(1)!),
};

String _trailerOf(String text) {
  final at = text.lastIndexOf('trailer');
  return at < 0 ? '' : text.substring(at);
}
