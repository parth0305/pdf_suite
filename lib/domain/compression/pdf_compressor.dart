import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfStreamBody;
import 'package:folio/domain/compression/compression_estimate.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

/// Rewrites [bytes] with duplicate objects collapsed, unreferenced objects
/// dropped, and uncompressed streams deflated.
///
/// Every step is exact: not one character of text and not one pixel changes.
/// Reducing image quality would need an encoder Folio does not have, and is
/// not attempted - see LIMITATIONS.
CompressionResult compressPdf(Uint8List bytes) {
  final objects = parsePdfObjects(bytes);
  final text = latin1.decode(bytes, allowInvalid: true);

  final canonical = _canonicalNumbers(objects);
  final rewritten = <PdfObject>[];

  for (final o in objects) {
    if (canonical[o.number] != o.number) continue;
    rewritten.add(_withReferencesRemapped(o, canonical));
  }

  // Reachability is computed AFTER remapping: an object referenced only by a
  // duplicate that was just collapsed is still referenced by its canonical
  // twin, and dropping it would break the document.
  final referenced = _referencedNumbers(
    rewritten.map((o) => latin1.decode(o.body, allowInvalid: true)).join('\n') +
        _trailerOf(text),
  );

  final kept = [
    for (final o in rewritten)
      if (referenced.contains(o.number)) _deflated(o),
  ];

  final out = writePdfDocument(bytes, kept.isEmpty ? rewritten : kept);

  // The breakdown explains WHERE the saving came from. It is deliberately not
  // the saving itself: the parts do not sum to the whole, because the rewrite
  // carries its own overhead.
  final originalReferenced = _referencedNumbers(text);

  return CompressionResult(
    bytes: out,
    originalBytes: bytes.length,
    duplicateBytes: objects
        .where((o) => canonical[o.number] != o.number)
        .fold(0, (sum, o) => sum + o.body.length),
    orphanedBytes: objects
        .where(
          (o) =>
              canonical[o.number] == o.number &&
              !originalReferenced.contains(o.number),
        )
        .fold(0, (sum, o) => sum + o.body.length),
    deflatableBytes: objects
        .where((o) => canonical[o.number] == o.number)
        .fold(0, (sum, o) => sum + _deflateSaving(o)),
  );
}

/// Maps every object number to the lowest number with byte-identical content.
///
/// Byte-identical only. Two objects that differ by whitespace mean the same
/// thing to a reader, but proving that needs a parser, and collapsing objects
/// that are merely equivalent is how a compressor corrupts a document.
Map<int, int> _canonicalNumbers(List<PdfObject> objects) {
  final firstSeen = <String, int>{};
  final canonical = <int, int>{};

  for (final o in objects) {
    // Tiny objects are not worth collapsing and are the most likely to be
    // coincidentally identical.
    if (o.body.length < 64) {
      canonical[o.number] = o.number;
      continue;
    }

    final key = latin1.decode(o.body, allowInvalid: true);
    final existing = firstSeen[key];
    if (existing == null) {
      firstSeen[key] = o.number;
      canonical[o.number] = o.number;
    } else {
      canonical[o.number] = existing;
    }
  }

  return canonical;
}

/// Every object number named as `N G R`, plus the catalog.
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

/// Points every reference at its canonical object.
///
/// Only the DICTIONARY is rewritten, never the stream payload: a compressed
/// stream is binary, and bytes that happen to read as `12 0 R` inside it are
/// image data, not a reference. Rewriting them corrupts the image.
PdfObject _withReferencesRemapped(PdfObject o, Map<int, int> canonical) {
  final body = latin1.decode(o.body, allowInvalid: true);
  final streamAt = body.indexOf('stream');
  final dict = streamAt < 0 ? body : body.substring(0, streamAt);

  final replaced = dict.replaceAllMapped(RegExp(r'(\d+)(\s+\d+\s+R)'), (m) {
    final number = int.parse(m.group(1)!);
    return '${canonical[number] ?? number}${m.group(2)}';
  });

  if (replaced == dict) return o;

  return PdfObject(
    number: o.number,
    generation: o.generation,
    body: [
      ...latin1.encode(replaced),
      if (streamAt >= 0) ...o.body.sublist(streamAt),
    ],
  );
}

/// How many bytes deflating this object's stream would save, NET.
///
/// The `/Filter /FlateDecode` declaration goes into the dictionary too, so a
/// stream that deflates by thirty bytes saves nine. Counting the gross figure
/// makes the estimate promise more than compressing delivers, and an estimate
/// that over-promises is worse than none.
int _deflateSaving(PdfObject o) {
  final payload = _uncompressedPayload(o);
  if (payload == null) return 0;

  final packed = pdfStreamBody(payload);
  if (packed.filter.isEmpty) return 0;

  return payload.length - packed.bytes.length - packed.filter.length;
}

/// The object with its stream deflated, if that helps.
PdfObject _deflated(PdfObject o) {
  final payload = _uncompressedPayload(o);
  if (payload == null) return o;

  final packed = pdfStreamBody(payload);
  if (packed.filter.isEmpty) return o;

  final body = latin1.decode(o.body, allowInvalid: true);
  final dict = body.substring(0, body.indexOf('stream'));

  // /Length must describe the bytes actually written. The old one describes
  // the text they came from.
  final newDict = dict.replaceFirst(
    RegExp(r'/Length\s+\d+'),
    '/Length ${packed.bytes.length}${packed.filter}',
  );

  return PdfObject(
    number: o.number,
    generation: o.generation,
    body: [
      // Trimmed: the original dictionary already ends with a newline, and
      // appending another leaves a blank line between `>>` and `stream`.
      ...latin1.encode('${newDict.trimRight()}\nstream\n'),
      ...packed.bytes,
      ...latin1.encode('\nendstream'),
    ],
  );
}

/// The stream payload of an object that has one and is not already filtered.
String? _uncompressedPayload(PdfObject o) {
  final body = latin1.decode(o.body, allowInvalid: true);
  final streamAt = body.indexOf('stream');
  if (streamAt < 0) return null;

  final dict = body.substring(0, streamAt);
  if (dict.contains('/Filter')) return null;
  if (!dict.contains('/Length')) return null;

  final start = body.indexOf('\n', streamAt);
  final end = body.lastIndexOf('endstream');
  if (start < 0 || end <= start + 1) return null;

  return body.substring(start + 1, end);
}
