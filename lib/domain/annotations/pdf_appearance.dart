import 'package:folio/domain/annotations/text_markup.dart';

/// Content stream for a markup annotation's appearance.
///
/// PDFium renders markup without an appearance stream - proven by probe - but
/// other viewers were not measurable here, and portability is the entire reason
/// annotations are written into the PDF. So one is always generated.
String appearanceStream(TextMarkup markup) {
  final colour = markup.pdfColour;
  final buffer = StringBuffer();

  switch (markup.kind) {
    case MarkupKind.highlight:
      // Multiply keeps the text legible underneath; without it the fill paints
      // over the glyphs and hides them.
      buffer.writeln('/GSHL gs');
      buffer.writeln('$colour rg');
      for (final q in markup.quads) {
        buffer.writeln(
          '${_n(q.left)} ${_n(q.bottom)} '
          '${_n(q.right - q.left)} ${_n(q.top - q.bottom)} re',
        );
      }
      buffer.writeln('f');

    case MarkupKind.underline:
      buffer.writeln('$colour RG');
      buffer.writeln('1 w');
      for (final q in markup.quads) {
        buffer.writeln('${_n(q.left)} ${_n(q.bottom)} m');
        buffer.writeln('${_n(q.right)} ${_n(q.bottom)} l');
      }
      buffer.writeln('S');

    case MarkupKind.strikeOut:
      buffer.writeln('$colour RG');
      buffer.writeln('1 w');
      for (final q in markup.quads) {
        final mid = (q.top + q.bottom) / 2;
        buffer.writeln('${_n(q.left)} ${_n(mid)} m');
        buffer.writeln('${_n(q.right)} ${_n(mid)} l');
      }
      buffer.writeln('S');
  }

  return buffer.toString();
}

/// The form XObject dictionary wrapping [appearanceStream].
String appearanceDict(TextMarkup markup, int streamLength) {
  final b = markup.boundingRect;
  final bbox = '[${_n(b.left)} ${_n(b.bottom)} ${_n(b.right)} ${_n(b.top)}]';

  final resources = markup.kind == MarkupKind.highlight
      ? '/Resources << /ExtGState << /GSHL << /Type /ExtGState '
            '/BM /Multiply /ca 1 >> >> >> '
      : '/Resources << >> ';

  return '<< /Type /XObject /Subtype /Form /BBox $bbox '
      '$resources/Length $streamLength >>';
}

/// Trims trailing zeros so the stream stays compact and readable.
String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}
