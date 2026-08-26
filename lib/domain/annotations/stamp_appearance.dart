import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfNumber, pdfString;

/// Content stream drawing a stamp: a box, then its label.
///
/// Coordinates are local to the appearance's BBox, which starts at the origin,
/// so the same stream works wherever the stamp is placed.
String stampAppearanceStream(Stamp stamp) {
  String channel(int shift) =>
      pdfNumber(((stamp.colorArgb >> shift) & 0xFF) / 255);
  final colour = '${channel(16)} ${channel(8)} ${channel(0)}';

  final w = stamp.widthPt;
  final h = stamp.heightPt;
  const inset = 1.0;

  return (StringBuffer()
        ..writeln('$colour RG')
        ..writeln('$colour rg')
        ..writeln('2 w')
        ..writeln(
          '${pdfNumber(inset)} ${pdfNumber(inset)} '
          '${pdfNumber(w - 2 * inset)} ${pdfNumber(h - 2 * inset)} re',
        )
        ..writeln('S')
        ..writeln('BT')
        ..writeln('/F1 ${pdfNumber(Stamp.fontSizePt)} Tf')
        ..writeln(
          '${pdfNumber(Stamp.paddingPt)} ${pdfNumber(Stamp.paddingPt)} Td',
        )
        ..writeln('${pdfString(stamp.label)} Tj')
        ..writeln('ET'))
      .toString();
}

/// The form XObject wrapping [stampAppearanceStream].
///
/// [fontObjectNumber] is the shared Helvetica object; every stamp in a save
/// references the same one.
String stampAppearanceDict(
  Stamp stamp,
  int streamLength,
  int fontObjectNumber,
) =>
    '<< /Type /XObject /Subtype /Form '
    '/BBox [0 0 ${pdfNumber(stamp.widthPt)} ${pdfNumber(stamp.heightPt)}] '
    '/Resources << /Font << /F1 $fontObjectNumber 0 R >> >> '
    '/Length $streamLength >>';

/// A standard-14 font: referenced, never embedded.
///
/// The fourteen standard fonts are built into every conforming viewer, so no
/// font data is shipped and no font licence is involved. Verified on device:
/// a non-embedded /Helvetica renders.
String helveticaFontObject() =>
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
    '/Encoding /WinAnsiEncoding >>';
