import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/ink_reshape.dart';
import 'package:folio/domain/annotations/drawing_appearance.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/annotations/annotation_transform.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// The only properties a restyle may change.
class AnnotationStyle {
  const AnnotationStyle({
    required this.colorArgb,
    required this.strokeWidth,
    this.contents,
  });

  final int colorArgb;
  final double strokeWidth;

  /// New text for a sticky note. Null leaves the existing text alone.
  final String? contents;

  @override
  bool operator ==(Object other) =>
      other is AnnotationStyle &&
      other.colorArgb == colorArgb &&
      other.strokeWidth == strokeWidth &&
      other.contents == contents;

  @override
  int get hashCode => Object.hash(colorArgb, strokeWidth, contents);
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
  required Map<int, TextRect> moved,
  Map<int, InkReshape> reshaped = const {},
}) {
  if (deleted.isEmpty &&
      restyled.isEmpty &&
      moved.isEmpty &&
      reshaped.isEmpty) {
    return pdf;
  }

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

  // The union, walked once. Emitting a second override of the same object
  // number means the later one wins and the earlier change vanishes.
  final touched = {...restyled.keys, ...moved.keys, ...reshaped.keys};
  for (final objectNumber in touched) {
    final target = _find(saved, objectNumber);
    if (target == null) continue;

    final destinationRect = moved[objectNumber];
    final requestedStyle = restyled[objectNumber];
    final newShape = reshaped[objectNumber];
    // A restyle we cannot honour - no reconstruction, so no appearance to
    // regenerate - and no move either means there is nothing to write. An
    // identical override would append an xref and a trailer for no change.
    if (destinationRect == null &&
        newShape == null &&
        (requestedStyle == null || target.reconstructed == null)) {
      continue;
    }

    // The move applies to the raw dictionary and needs no reconstruction,
    // which is why a stamp can move even though it cannot be restyled.
    var dict = target.rawDictionary;
    if (destinationRect != null) {
      dict = transformAnnotationDict(
        dict,
        from: target.rectPt,
        to: destinationRect,
      );
    }

    // A reshape replaces the geometry outright, so it is written from the
    // reconstructed strokes rather than transformed out of the old dictionary.
    // Only ink has points to reshape.
    final ink = target.reconstructed;
    if (newShape != null && ink is DrawingAnnotation) {
      final reshapedAnnotation = DrawingAnnotation(
        kind: ink.kind,
        pageIndex: ink.pageIndex,
        strokes: newShape.strokes,
        colorArgb: requestedStyle?.colorArgb ?? ink.colorArgb,
        strokeWidth: requestedStyle?.strokeWidth ?? ink.strokeWidth,
      );

      final stream = drawingAppearanceStream(reshapedAnnotation);
      final apNum = nextObj++;
      emit(
        apNum,
        '${drawingAppearanceDict(reshapedAnnotation, stream.length)}\n'
        'stream\n${stream}endstream',
      );

      emit(objectNumber, _inkDictionary(dict, newShape, apNum));
      continue;
    }

    if (requestedStyle == null || target.reconstructed == null) {
      emit(objectNumber, dict);
      continue;
    }

    final restyledAnnotation = _withStyle(
      target.reconstructed!,
      requestedStyle,
    );

    // A note has no appearance stream; adding one would disagree with the icon
    // every viewer already draws.
    int? apNum;
    // ImageAnnotation is excluded with StickyNote, for a different reason:
    // a note has no appearance, and a photographed signature has one that no
    // restyle could regenerate. Neither is reachable here - the editor rebuilds
    // annotations it READ from a PDF, and it never reads an image back as one -
    // but the sealed switch has to say so.
    if (restyledAnnotation is! StickyNote &&
        restyledAnnotation is! ImageAnnotation) {
      final (stream, apDict) = switch (restyledAnnotation) {
        // Excluded by the guard above; the sealed switch still requires it.
        ImageAnnotation() => throw StateError(
          'image annotations are not restyled',
        ),
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
        StickyNote() || Stamp() => throw StateError('unreachable'),
      };
      apNum = nextObj++;
      emit(apNum, '$apDict\nstream\n${stream}endstream');
    }

    // The TRANSFORMED dictionary, so a move and a restyle compose into one
    // override rather than two that overwrite each other.
    emit(objectNumber, _restyledDictionary(dict, requestedStyle, apNum));
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
      // A photograph has no colour or stroke width to restyle. Returned
      // unchanged rather than silently dropped.
      ImageAnnotation() => annotation,
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
      StickyNote() => StickyNote(
        pageIndex: annotation.pageIndex,
        anchorPt: annotation.anchorPt,
        contents: style.contents ?? annotation.contents,
        colorArgb: style.colorArgb,
      ),
      Stamp() => annotation,
    };

/// Rewrites only `/C`, `/BS` and `/AP`, leaving every other key - including
/// all geometry - exactly as it was in the source dictionary.
String _restyledDictionary(String source, AnnotationStyle style, int? apNum) {
  String colour(int shift) =>
      pdfNumber(((style.colorArgb >> shift) & 0xFF) / 255);
  final c = '/C [${colour(16)} ${colour(8)} ${colour(0)}]';
  // A /Text icon has no stroke, so /BS would describe nothing.
  final isNote = RegExp(r'/Subtype\s*/Text\b').hasMatch(source);
  final bs = isNote ? '' : ' /BS << /W ${pdfNumber(style.strokeWidth)} >>';
  final ap = apNum == null ? '' : ' /AP << /N $apNum 0 R >>';

  var body = source.substring(2, source.length - 2).trim();
  body = body.replaceAll(RegExp(r'/C\s*\[[^\]]*\]'), '');
  body = body.replaceAll(RegExp(r'/BS\s*<<[^>]*>>'), '');
  body = body.replaceAll(RegExp(r'/AP\s*<<[^>]*>>'), '');
  if (style.contents != null) {
    body = body.replaceAll(
      RegExp(r'/Contents\s*\([^)]*\)'),
      '/Contents ${pdfString(style.contents!)}',
    );
  }
  body = body.replaceAll(RegExp(r'\s+'), ' ').trim();

  return '<< $body $c$bs$ap >>';
}

/// The annotation dictionary with a reshaped /InkList, /Rect and /AP.
///
/// The rectangle MUST follow the points: one left where it was clips the
/// appearance, so the reshaped stroke is drawn and then cut off - which looks
/// like the reshape failed rather than like a stale rectangle.
String _inkDictionary(String dict, InkReshape shape, int apNum) {
  final inkList = shape.strokes
      .map(
        (stroke) =>
            '[${stroke.map((p) => '${pdfNumber(p.x)} ${pdfNumber(p.y)}').join(' ')}]',
      )
      .join(' ');

  var out = dict.replaceFirst(
    RegExp(r'/InkList\s*\[.*?\]\s*\]', dotAll: true),
    '/InkList [$inkList]',
  );

  final r = shape.rect;
  out = out.replaceFirst(
    RegExp(r'/Rect\s*\[[^\]]*\]'),
    '/Rect [${pdfNumber(r.left)} ${pdfNumber(r.bottom)} '
    '${pdfNumber(r.right)} ${pdfNumber(r.top)}]',
  );

  // Matches the /AP entry ALONE. A looser pattern - `<<[^>]*>>\\s*>>` - also
  // swallowed the dictionary's own closing braces, and the annotation was
  // emitted unterminated: the appearance was correct and nothing could read
  // the dictionary that pointed at it.
  final replaced = out.replaceFirst(
    RegExp(r'/AP\s*<<\s*/N\s+\d+\s+\d+\s+R\s*>>'),
    '/AP << /N $apNum 0 R >>',
  );

  // An annotation that had no appearance yet gets one.
  if (replaced == out) {
    return out.replaceFirst(RegExp(r'>>\s*$'), '/AP << /N $apNum 0 R >> >>');
  }

  return replaced;
}
