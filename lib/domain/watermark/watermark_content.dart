import 'dart:math' as math;

import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfNumber, pdfString;
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// The resource names the watermark introduces into a page's /Resources.
///
/// Prefixed so they cannot collide with names the page's own content already
/// uses - a page with its own /F1 would otherwise start drawing in our font.
const watermarkFontName = 'WMF1';
const watermarkGStateName = 'WMGS';

/// Rough advance width of mixed-case Helvetica, used only to centre the text.
/// Carrying a metrics table for a font we do not embed is not worth it.
const _averageGlyphWidth = 0.6;

/// Content drawing [mark] centred on a page of [mediaBox].
///
/// Wrapped in q ... Q: this runs after the page's own content, and an
/// unbalanced stream leaks graphics state into everything appended after it.
String watermarkContentStream(Watermark mark, {required TextRect mediaBox}) {
  final centreX = (mediaBox.left + mediaBox.right) / 2;
  final centreY = (mediaBox.bottom + mediaBox.top) / 2;

  final width = mark.text.length * mark.fontSizePt * _averageGlyphWidth;
  // Text is drawn from its baseline, so drop by roughly a third of the size
  // to sit the visual centre of the glyphs on the page centre.
  final offsetX = -width / 2;
  final offsetY = -mark.fontSizePt / 3;

  String channel(int shift) =>
      pdfNumber(((mark.colorArgb >> shift) & 0xFF) / 255);

  final buffer = StringBuffer()
    ..writeln('q')
    ..writeln('/$watermarkGStateName gs')
    ..writeln('${channel(16)} ${channel(8)} ${channel(0)} rg')
    ..writeln('1 0 0 1 ${pdfNumber(centreX)} ${pdfNumber(centreY)} cm');

  if (mark.rotation == WatermarkRotation.diagonal) {
    // Roughly the diagonal of a portrait page.
    const radians = 55 * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    // Negate the VALUE, not the formatted string: '-${pdfNumber(sin)}' yields
    // '--0.5' the moment sin is negative.
    buffer.writeln(
      '${pdfNumber(cos)} ${pdfNumber(sin)} '
      '${pdfNumber(-sin)} ${pdfNumber(cos)} 0 0 cm',
    );
  }

  buffer
    ..writeln('BT')
    ..writeln('/$watermarkFontName ${pdfNumber(mark.fontSizePt)} Tf')
    ..writeln('${pdfNumber(offsetX)} ${pdfNumber(offsetY)} Td')
    ..writeln('${pdfString(mark.text)} Tj')
    ..writeln('ET')
    ..write('Q');

  return buffer.toString();
}

/// The graphics state carrying the watermark's opacity.
///
/// Opacity belongs here rather than in a pale fill colour: a pale colour looks
/// wrong over dark content, and it is not something a viewer can reason about.
String watermarkExtGState(Watermark mark) =>
    '<< /Type /ExtGState /ca ${pdfNumber(mark.opacity)} '
    '/CA ${pdfNumber(mark.opacity)} >>';
