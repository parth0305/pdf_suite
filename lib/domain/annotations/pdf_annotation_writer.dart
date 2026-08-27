import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/drawing_appearance.dart';
import 'package:folio/domain/annotations/image_appearance.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/stamp_appearance.dart';
import 'package:folio/domain/annotations/annotation.dart';

/// Writes [annotations] into [pdf] as real annotation objects, by appending a
/// PDF incremental update.
///
/// The original bytes are never rewritten: new objects, an overridden page
/// dictionary carrying /Annots, a new xref section and a trailer chaining to
/// the previous one are appended. Readers walk that chain backwards.
///
/// Throws [UnsupportedPdfStructure] for documents this technique cannot handle,
/// rather than producing a file whose annotations silently never appear.
Uint8List writeAnnotations(Uint8List pdf, List<Annotation> annotations) {
  if (annotations.isEmpty) return pdf;

  final text = latin1.decode(pdf, allowInvalid: true);
  final reader = PdfObjectReader.parse(text);

  if (reader.usesXrefStream) {
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

  /// Emits a stream object, compressed when that actually helps.
  ///
  /// The bytes are appended directly rather than spliced into a string:
  /// deflate output is binary and would not survive latin1 round-tripping.
  /// [dictWithoutLength] must not carry /Length or /Filter - both are derived
  /// from the bytes actually written.
  /// Emits an object whose stream is already-compressed BINARY.
  ///
  /// Separate from [emitStream], which takes text and decides whether to
  /// deflate it. Image samples are deflated by the caller and must be written
  /// through untouched; running them through the text path would try to
  /// latin1-encode bytes that are not text.
  void emitBinary(int number, String dict, List<int> bytes) {
    offsets[number] = out.length;
    out
      ..addAll(latin1.encode('$number 0 obj\n$dict\nstream\n'))
      ..addAll(bytes)
      ..addAll(latin1.encode('\nendstream\nendobj\n'));
  }

  void emitStream(int number, String dictWithoutLength, String content) {
    final body = pdfStreamBody(content);
    offsets[number] = out.length;
    out
      ..addAll(
        latin1.encode(
          '$number 0 obj\n'
          '$dictWithoutLength /Length ${body.bytes.length}${body.filter} >>\n'
          'stream\n',
        ),
      )
      ..addAll(body.bytes)
      ..addAll(latin1.encode('\nendstream\nendobj\n'));
  }

  // Group by page: each page is overridden once, however many annotations it
  // has.
  final byPage = <int, List<Annotation>>{};
  for (final a in annotations) {
    byPage.putIfAbsent(a.pageIndex, () => []).add(a);
  }

  // One font object per save, shared by every stamp. Standard-14: referenced,
  // never embedded.
  int? fontObjNum;
  if (annotations.any((a) => a is Stamp)) {
    fontObjNum = nextObj++;
    emit(fontObjNum, helveticaFontObject());
  }

  for (final entry in byPage.entries) {
    final page = reader.pageAt(entry.key);
    if (page == null) {
      throw UnsupportedPdfStructure(
        technicalDetail: 'no page object at index ${entry.key}',
      );
    }

    final newRefs = <String>[];
    for (final annotation in entry.value) {
      // An image annotation is emitted separately: its appearance references
      // two binary objects that must exist first, which the shared
      // (stream, dict) shape below cannot express.
      if (annotation is ImageAnnotation) {
        final parts = imageAppearanceParts(annotation);

        final maskNum = nextObj++;
        emitBinary(maskNum, maskXObjectDict(parts), parts.alpha);

        final imageNum = nextObj++;
        emitBinary(imageNum, imageXObjectDict(parts, maskNum), parts.rgb);

        final apNum = nextObj++;
        emitStream(
          apNum,
          _withoutLength(
            imageAppearanceDict(annotation, parts, 0, '', imageNum),
          ),
          parts.content,
        );

        final annotNum = nextObj++;
        emit(annotNum, _annotationDict(annotation, apNum));
        newRefs.add('$annotNum 0 R');
        continue;
      }

      // Nullable: a /Text note has no appearance stream at all.
      final (String, String)? appearance = switch (annotation) {
        TextMarkup() => (
          appearanceStream(annotation),
          appearanceDict(annotation, appearanceStream(annotation).length),
        ),
        DrawingAnnotation() => (
          drawingAppearanceStream(annotation),
          drawingAppearanceDict(
            annotation,
            drawingAppearanceStream(annotation).length,
          ),
        ),
        Stamp() => (
          stampAppearanceStream(annotation),
          stampAppearanceDict(
            annotation,
            stampAppearanceStream(annotation).length,
            fontObjNum!,
          ),
        ),
        StickyNote() => null,
        // Handled above; it never reaches here.
        ImageAnnotation() => null,
      };

      int? apNum;
      if (appearance != null) {
        final (stream, dict) = appearance;
        apNum = nextObj++;
        emitStream(apNum, _withoutLength(dict), stream);
      }

      final annotNum = nextObj++;
      emit(annotNum, _annotationDict(annotation, apNum));
      newRefs.add('$annotNum 0 R');
    }

    emit(page.objectNumber, reader.withAnnots(page, newRefs));
  }

  // One xref subsection per object: always valid, and avoids having to detect
  // runs of consecutive numbers.
  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  final numbers = offsets.keys.toList()..sort();
  for (final n in numbers) {
    buffer.writeln('$n 1');
    buffer.writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');
  buffer.writeln(
    '<< /Size $nextObj /Root ${root.group(1)} ${root.group(2)} R '
    '/Prev $prevOffset >>',
  );
  buffer.writeln('startxref');
  buffer.writeln('$xrefOffset');
  buffer.write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}

/// The annotation dictionary. Geometry differs per subtype: markup uses
/// /QuadPoints, ink uses /InkList, a line uses /L, and shapes use /Rect alone.
String _annotationDict(Annotation annotation, int? apNum) {
  final ap = apNum == null ? '' : ' /AP << /N $apNum 0 R >>';

  switch (annotation) {
    case TextMarkup():
      final b = annotation.boundingRect;
      return '<< /Type /Annot /Subtype /${annotation.pdfSubtype} '
          '/Rect [${pdfNumber(b.left)} ${pdfNumber(b.bottom)} '
          '${pdfNumber(b.right)} ${pdfNumber(b.top)}] '
          '/QuadPoints [${annotation.quadPoints.map(pdfNumber).join(' ')}] '
          '/C [${annotation.pdfColour}] /CA 1 /F 4$ap >>';

    case StickyNote():
      final r = annotation.anchorPt;
      const size = StickyNote.iconSizePt;
      return '<< /Type /Annot /Subtype /Text '
          '/Rect [${pdfNumber(r.x)} ${pdfNumber(r.y - size)} '
          '${pdfNumber(r.x + size)} ${pdfNumber(r.y)}] '
          '/Contents ${pdfString(annotation.contents)} '
          '/Name /Note /C [${_colourOf(annotation.colorArgb)}] /CA 1 /F 4'
          '$ap >>';

    case ImageAnnotation():
      final r = annotation.rect;
      return '<< /Type /Annot /Subtype /Stamp '
          '/Rect [${pdfNumber(r.left)} ${pdfNumber(r.bottom)} '
          '${pdfNumber(r.right)} ${pdfNumber(r.top)}] '
          '/Name /Signature /CA 1 /F 4$ap >>';

    case Stamp():
      final r = annotation.anchorPt;
      // /Name records the preset so a reader can tell them apart.
      final name = annotation.preset.name;
      final capitalised = name[0].toUpperCase() + name.substring(1);
      return '<< /Type /Annot /Subtype /Stamp '
          '/Rect [${pdfNumber(r.x)} ${pdfNumber(r.y - annotation.heightPt)} '
          '${pdfNumber(r.x + annotation.widthPt)} ${pdfNumber(r.y)}] '
          '/Name /$capitalised '
          '/C [${_colourOf(annotation.colorArgb)}] /CA 1 /F 4'
          '$ap >>';

    case DrawingAnnotation():
      final b = annotation.boundsPt;
      final rect =
          '/Rect [${pdfNumber(b.left)} ${pdfNumber(b.bottom)} '
          '${pdfNumber(b.right)} ${pdfNumber(b.top)}]';
      final common =
          '/Type /Annot /Subtype /${annotation.pdfSubtype} $rect '
          '/C [${annotation.pdfColour}] /CA 1 /F 4 '
          '/BS << /W ${pdfNumber(annotation.strokeWidth)} >>';

      final geometry = switch (annotation.kind) {
        DrawingKind.ink =>
          ' /InkList [${annotation.strokes.map((stroke) => '[${stroke.map((p) => '${pdfNumber(p.x)} ${pdfNumber(p.y)}').join(' ')}]').join(' ')}]',
        DrawingKind.line =>
          ' /L [${pdfNumber(annotation.points.first.x)} '
              '${pdfNumber(annotation.points.first.y)} '
              '${pdfNumber(annotation.points.last.x)} '
              '${pdfNumber(annotation.points.last.y)}]',
        // /OpenArrow at the end of the shaft; viewers that honour /LE draw the
        // head themselves, and our /AP draws it for those that do not.
        DrawingKind.arrow =>
          ' /L [${pdfNumber(annotation.points.first.x)} '
              '${pdfNumber(annotation.points.first.y)} '
              '${pdfNumber(annotation.points.last.x)} '
              '${pdfNumber(annotation.points.last.y)}]'
              ' /LE [/None /OpenArrow]',
        DrawingKind.rectangle || DrawingKind.ellipse => '',
      };

      return '<< $common$geometry$ap >>';
  }
}

String _colourOf(int argb) {
  String channel(int shift) => pdfNumber(((argb >> shift) & 0xFF) / 255);
  return '${channel(16)} ${channel(8)} ${channel(0)}';
}

/// Strips the trailing `>>` and any `/Length` from an appearance dictionary,
/// so the stream emitter can derive both from the bytes it actually writes.
String _withoutLength(String dict) {
  var body = dict.trimRight();
  if (body.endsWith('>>')) {
    body = body.substring(0, body.length - 2).trimRight();
  }
  return body.replaceAll(RegExp(r'/Length\s+\d+'), '').trimRight();
}
