import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/drawing_appearance.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';

/// The only properties a restyle may change.
class AnnotationStyle {
  const AnnotationStyle({required this.colorArgb, required this.strokeWidth});

  final int colorArgb;
  final double strokeWidth;

  @override
  bool operator ==(Object other) =>
      other is AnnotationStyle &&
      other.colorArgb == colorArgb &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(colorArgb, strokeWidth);
}

/// Applies deletions and restyles as one PDF incremental update.
///
/// The original bytes are never rewritten. Deleting drops a reference from an
/// overridden page dictionary, which leaves the annotation object in the file
/// but unreferenced, so it stops rendering. Restyling overrides the
/// annotation's own object number.
///
/// Geometry keys are copied out of the source dictionary as raw substrings.
/// Re-emitting them from parsed doubles would round to two decimals and move
/// the annotation - a corruption invisible until someone compared renders.
Uint8List applyAnnotationEdits(
  Uint8List pdf, {
  required Set<int> deleted,
  required Map<int, AnnotationStyle> restyled,
}) {
  if (deleted.isEmpty && restyled.isEmpty) return pdf;

  final text = latin1.decode(pdf, allowInvalid: true);
  final pages = PdfObjectReader.parse(text);

  if (pages.usesXrefStream) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'PDF 1.5+ cross-reference stream',
    );
  }

  final startxref = RegExp(
    r'startxref\s+(\d+)\s*%%EOF\s*$',
  ).firstMatch(text.trimRight());
  final roots = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  final sizes = RegExp(r'/Size\s+(\d+)').allMatches(text);

  if (startxref == null || roots.isEmpty || sizes.isEmpty) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'no classic trailer with /Root, /Size and startxref',
    );
  }

  // The newest trailer wins, so one that omits /Info silently discards the
  // document's title and author. Carry the existing reference forward.
  final info = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  final infoEntry = info.isEmpty
      ? ''
      : ' /Info ${info.last.group(1)} ${info.last.group(2)} R';

  final saved = PdfAnnotationReader.parse(text);
  final prevOffset = int.parse(startxref.group(1)!);
  final root = roots.last;
  var nextObj = int.parse(sizes.last.group(1)!);

  final out = <int>[...pdf];
  if (out.isNotEmpty && out.last != 0x0a) out.add(0x0a);

  final offsets = <int, int>{};
  void emit(int number, String body) {
    offsets[number] = out.length;
    out.addAll(latin1.encode('$number 0 obj\n$body\nendobj\n'));
  }

  // Restyle: override the annotation's own object, with a fresh appearance.
  for (final entry in restyled.entries) {
    final target = _find(saved, entry.key);
    if (target?.reconstructed == null) continue;

    final restyledAnnotation = _withStyle(target!.reconstructed!, entry.value);

    final (stream, dict) = switch (restyledAnnotation) {
      TextMarkup() => (
        appearanceStream(restyledAnnotation),
        appearanceDict(
          restyledAnnotation,
          appearanceStream(restyledAnnotation).length,
        ),
      ),
      DrawingAnnotation() => (
        drawingAppearanceStream(restyledAnnotation),
        drawingAppearanceDict(
          restyledAnnotation,
          drawingAppearanceStream(restyledAnnotation).length,
        ),
      ),
    };

    final apNum = nextObj++;
    emit(apNum, '$dict\nstream\n${stream}endstream');
    emit(
      target.objectNumber,
      _restyledDictionary(target.rawDictionary, entry.value, apNum),
    );
  }

  // Delete: override each affected page with the surviving references.
  if (deleted.isNotEmpty) {
    for (var pageIndex = 0; ; pageIndex++) {
      final page = pages.pageAt(pageIndex);
      if (page == null) break;

      final survivors = page.existingAnnotRefs
          .where((ref) => !deleted.contains(int.parse(ref.split(' ').first)))
          .toList();
      if (survivors.length == page.existingAnnotRefs.length) continue;

      emit(
        page.objectNumber,
        page.rawDictionary.replaceFirst(
          RegExp(r'/Annots\s*\[[^\]]*\]'),
          '/Annots [${survivors.join(' ')}]',
        ),
      );
    }
  }

  if (offsets.isEmpty) return pdf;

  // One xref subsection per object: always valid, and avoids having to detect
  // runs of consecutive numbers.
  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  for (final n in offsets.keys.toList()..sort()) {
    buffer.writeln('$n 1');
    buffer.writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');
  buffer.writeln(
    '<< /Size $nextObj /Root ${root.group(1)} ${root.group(2)} R'
    '$infoEntry /Prev $prevOffset >>',
  );
  buffer.writeln('startxref');
  buffer.writeln('$xrefOffset');
  buffer.write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}

SavedAnnotation? _find(PdfAnnotationReader reader, int objectNumber) {
  for (final a in reader.all) {
    if (a.objectNumber == objectNumber) return a;
  }
  return null;
}

Annotation _withStyle(Annotation annotation, AnnotationStyle style) =>
    switch (annotation) {
      TextMarkup() => TextMarkup(
        kind: annotation.kind,
        pageIndex: annotation.pageIndex,
        quads: annotation.quads,
        colorArgb: style.colorArgb,
      ),
      DrawingAnnotation() => DrawingAnnotation(
        kind: annotation.kind,
        pageIndex: annotation.pageIndex,
        strokes: [annotation.points],
        colorArgb: style.colorArgb,
        strokeWidth: style.strokeWidth,
      ),
    };

/// Rewrites only `/C`, `/BS` and `/AP`, leaving every other key - including
/// all geometry - exactly as it was in the source dictionary.
String _restyledDictionary(String source, AnnotationStyle style, int apNum) {
  String colour(int shift) =>
      pdfNumber(((style.colorArgb >> shift) & 0xFF) / 255);
  final c = '/C [${colour(16)} ${colour(8)} ${colour(0)}]';
  final bs = '/BS << /W ${pdfNumber(style.strokeWidth)} >>';
  final ap = '/AP << /N $apNum 0 R >>';

  var body = source.substring(2, source.length - 2).trim();
  body = body.replaceAll(RegExp(r'/C\s*\[[^\]]*\]'), '');
  body = body.replaceAll(RegExp(r'/BS\s*<<[^>]*>>'), '');
  body = body.replaceAll(RegExp(r'/AP\s*<<[^>]*>>'), '');
  body = body.replaceAll(RegExp(r'\s+'), ' ').trim();

  return '<< $body $c $bs $ap >>';
}
