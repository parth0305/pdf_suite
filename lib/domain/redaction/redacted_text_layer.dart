import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/redaction/redaction_box.dart';

/// The indices in [text] whose characters survive [boxes] on [pageIndex].
///
/// A character is dropped when its rect **intersects** a box, not when a box
/// contains it. Half a glyph is often enough to read, and a character the user
/// dragged a box across is a character they meant to remove.
List<int> survivingIndices(
  PageText text,
  List<RedactionBox> boxes,
  int pageIndex,
) {
  final onThisPage = boxes.where((b) => b.pageIndex == pageIndex).toList();
  if (onThisPage.isEmpty) {
    return [for (var i = 0; i < text.charRects.length; i++) i];
  }

  return [
    for (var i = 0; i < text.charRects.length; i++)
      if (!onThisPage.any((b) => _intersects(text.charRects[i], b.rect))) i,
  ];
}

/// True when the rectangles overlap at all. Touching edges do not count: a box
/// whose right edge sits exactly on a glyph's left edge covers none of it.
bool _intersects(TextRect a, TextRect b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.bottom < b.top &&
    b.bottom < a.top;

/// The invisible text a redacted page carries so search and selection still
/// work for everything that was not removed.
///
/// Text render mode 3 paints nothing but remains extractable. Each character
/// is positioned by its own text matrix from the rect PDFium reported, because
/// word and line structure is not reconstructed - extraction only needs the
/// characters in their original order.
String invisibleTextStream(PageText text, List<int> keep) {
  final buffer = StringBuffer();

  for (final i in keep) {
    final c = text.fullText[i];
    if (!_isDrawable(c)) continue;

    final rect = text.charRects[i];
    buffer.writeln(
      'BT 3 Tr /RdF1 ${_number(rect.height)} Tf '
      '1 0 0 1 ${_number(rect.left)} ${_number(rect.bottom)} Tm '
      '${_escaped(c)} Tj ET',
    );
  }

  return buffer.toString();
}

/// WinAnsiEncoding covers Latin-1 plus a handful of typographic characters.
/// Anything else has no glyph in a non-embedded standard-14 font, so emitting
/// its byte would draw a different character. Omitting it loses searchability
/// for that character and nothing else.
bool _isDrawable(String c) {
  final code = c.codeUnitAt(0);
  if (code > 0xFF) return false;
  // Control characters and the space have no glyph worth positioning.
  return code > 0x20;
}

String _escaped(String c) =>
    '(${c.replaceAllMapped(RegExp(r'[\\()]'), (m) => '\\${m[0]}')})';

/// Trims a trailing `.0` so the stream reads like the rest of Folio's output.
String _number(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}
