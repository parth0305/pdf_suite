import 'dart:convert';
import 'dart:io';

import 'package:folio/domain/annotations/annotation.dart';

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
          '${pdfNumber(q.left)} ${pdfNumber(q.bottom)} '
          '${pdfNumber(q.right - q.left)} ${pdfNumber(q.top - q.bottom)} re',
        );
      }
      buffer.writeln('f');

    case MarkupKind.underline:
      buffer.writeln('$colour RG');
      buffer.writeln('1 w');
      for (final q in markup.quads) {
        buffer.writeln('${pdfNumber(q.left)} ${pdfNumber(q.bottom)} m');
        buffer.writeln('${pdfNumber(q.right)} ${pdfNumber(q.bottom)} l');
      }
      buffer.writeln('S');

    case MarkupKind.strikeOut:
      buffer.writeln('$colour RG');
      buffer.writeln('1 w');
      for (final q in markup.quads) {
        final mid = (q.top + q.bottom) / 2;
        buffer.writeln('${pdfNumber(q.left)} ${pdfNumber(mid)} m');
        buffer.writeln('${pdfNumber(q.right)} ${pdfNumber(mid)} l');
      }
      buffer.writeln('S');
  }

  return buffer.toString();
}

/// The form XObject dictionary wrapping [appearanceStream].
String appearanceDict(TextMarkup markup, int streamLength) {
  final b = markup.boundingRect;
  final bbox =
      '[${pdfNumber(b.left)} ${pdfNumber(b.bottom)} ${pdfNumber(b.right)} ${pdfNumber(b.top)}]';

  final resources = markup.kind == MarkupKind.highlight
      ? '/Resources << /ExtGState << /GSHL << /Type /ExtGState '
            '/BM /Multiply /ca 1 >> >> >> '
      : '/Resources << >> ';

  return '<< /Type /XObject /Subtype /Form /BBox $bbox '
      '$resources/Length $streamLength >>';
}

/// Formats a PDF number compactly: two decimals at most, trailing zeros
/// trimmed. Shared with the annotation writer so coordinates are written the
/// same way everywhere rather than as verbose Dart doubles.
String pdfNumber(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Wraps [text] as a PDF literal string, escaping the characters that would
/// otherwise end it early. Shared so every writer escapes identically - three
/// private copies of an escaping rule is how one of them ends up wrong.
String pdfString(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
  return '($escaped)';
}

/// A stream's bytes and the dictionary entries describing them.
///
/// Compressed ONLY when compression actually helps. Deflate has overhead, so a
/// forty-byte appearance stream comes out bigger - compressing unconditionally
/// would make Folio's output larger, which is the opposite of the point.
///
/// The comparison counts the `/Filter` declaration, because that text goes
/// into the file too. Without it a stream that deflates by twelve bytes still
/// grows the document by nine, and a three-page watermark grew by 27.
///
/// zlib comes from dart:io, so this costs no dependency.
({List<int> bytes, String filter}) pdfStreamBody(String content) {
  const filter = ' /Filter /FlateDecode';

  final raw = latin1.encode(content);
  if (raw.isEmpty) return (bytes: raw, filter: '');

  final deflated = ZLibCodec(level: 9).encode(raw);
  if (deflated.length + filter.length >= raw.length) {
    return (bytes: raw, filter: '');
  }

  return (bytes: deflated, filter: filter);
}
