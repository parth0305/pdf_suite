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
/// Characters are emitted in **runs**, not one at a time. PDFium inserts a
/// word-break space wherever it sees a gap between glyphs, and a page whose
/// every character is its own text object extracts as `C o n f i d e n t i a l`
/// - which no search would match. Within a single `Tj` the reader spaces
/// glyphs by the font's own advances, so a run comes back as one word.
///
/// A run breaks wherever the original text did: at any character with no
/// glyph - which is every space and every line break PDFium reports - and,
/// critically, wherever a character was **removed**. Without that last rule
/// the halves either side of a redaction would be joined into a word that
/// never existed.
///
/// Runs are NOT broken by comparing glyph rectangles. A descender sits lower
/// than its neighbours and a hyphen sits higher, so a same-line test on rect
/// geometry splits `rupees` into `ru p ees` and `REDACT-ME-9931` into
/// `REDACT - ME - 9931`. The text's own whitespace is the only reliable
/// separator.
String invisibleTextStream(PageText text, List<int> keep) {
  final buffer = StringBuffer();
  final kept = keep.toSet();

  var i = 0;
  while (i < text.charRects.length) {
    if (!kept.contains(i) || !_isDrawable(text.fullText[i])) {
      i++;
      continue;
    }

    final start = i;
    final run = StringBuffer();
    while (i < text.charRects.length &&
        kept.contains(i) &&
        _isDrawable(text.fullText[i])) {
      run.write(text.fullText[i]);
      i++;
    }

    final rect = text.charRects[start];
    buffer.writeln(
      'BT 3 Tr /RdF1 ${_number(rect.height)} Tf '
      '1 0 0 1 ${_number(rect.left)} ${_number(rect.bottom)} Tm '
      '${_escaped(run.toString())} Tj ET',
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
  // Control characters and the space have no glyph worth positioning; they
  // also end a run, which is what puts a space back in the extracted text.
  return code > 0x20;
}

String _escaped(String s) =>
    '(${s.replaceAllMapped(RegExp(r'[\\()]'), (m) => '\\${m[0]}')})';

/// Trims a trailing `.0` so the stream reads like the rest of Folio's output.
String _number(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}
