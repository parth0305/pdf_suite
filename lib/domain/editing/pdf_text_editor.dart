import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/editing/font_encoding.dart';
import 'package:folio/domain/editing/pdf_font_resources.dart';
import 'package:folio/domain/editing/text_edit.dart';
import 'package:folio/domain/editing/text_run_finder.dart';

/// A run of text on a page, with everything needed to change it.
class EditableRun {
  const EditableRun({
    required this.run,
    required this.text,
    required this.pageIndex,
    required this.contentObject,
    required this.availableWidth,
    required this.font,
  });

  final TextRun run;

  /// What it says, or null when the font gives no way to read it. Shown as
  /// uneditable rather than guessed at.
  final String? text;

  final int pageIndex;

  /// The object whose stream this run lives in. A page may have several.
  final int contentObject;

  /// Room before whatever is drawn next on the same line, in points, or null
  /// when there is nothing after it.
  final double? availableWidth;

  final PageFont? font;

  /// Whether any edit to this run is possible at all.
  ///
  /// Includes knowing the glyph widths: without them no replacement can be
  /// fitted, so every edit would be refused. A run shown as editable that
  /// refuses everything typed into it is worse than one shown as fixed.
  bool get isEditable =>
      text != null &&
      run.isVisible &&
      font?.decoder != null &&
      (font!.widths.isNotEmpty || font!.byCode != null);

  double get x => run.position.x;
  double get y => run.position.y;
}

/// Reads and edits the text on a document's pages.
///
/// Works from the bytes rather than from a rendered page: the instructions are
/// what get changed, and everything else in the file is left exactly as it is.
class PdfTextEditor {
  PdfTextEditor._(this._pdf, this._index, this._reader);

  final Uint8List _pdf;
  final PdfObjectIndex _index;
  final PdfObjectReader _reader;

  static PdfTextEditor parse(Uint8List pdf) {
    final text = latin1.decode(pdf, allowInvalid: true);

    return PdfTextEditor._(
      pdf,
      PdfObjectIndex.parse(text),
      PdfObjectReader.parse(text),
    );
  }

  /// Every run of text on [pageIndex], in the order the page draws them.
  List<EditableRun> runsOn(int pageIndex) {
    final page = _reader.pageAt(pageIndex);
    if (page == null) return const [];

    final fonts = pageFonts(_pdf, _index, page.rawDictionary);
    final out = <EditableRun>[];

    for (final object in _contentObjects(page.rawDictionary)) {
      final stream = streamContents(_pdf, _index, object);
      if (stream == null) continue;

      final runs = findTextRuns(stream);

      for (var i = 0; i < runs.length; i++) {
        final run = runs[i];
        final font = run.fontName == null ? null : fonts[run.fontName];

        out.add(
          EditableRun(
            run: run,
            text: font?.decoder?.decode(run.bytes),
            pageIndex: pageIndex,
            contentObject: object,
            availableWidth: _roomAfter(runs, i, font),
            font: font,
          ),
        );
      }
    }

    return out;
  }

  /// What replacing [run]'s text would do, without doing it.
  EditPlan plan(EditableRun run, String replacement) {
    final decoder = run.font?.decoder;
    if (decoder == null) {
      return const EditRefused(EditRefusal.unreadable);
    }

    return planTextEdit(
      run: run.run,
      replacement: replacement,
      decoder: decoder,
      widthOf: (code) => run.font!.widthOf(code),
      availableWidth: run.availableWidth,
    );
  }

  /// The document with [run]'s text replaced, as an incremental update.
  ///
  /// The original bytes are never rewritten. The content stream is replaced by
  /// a new definition of the same object, appended at the end - so a reader
  /// walking the trailer chain sees the edit and everything before it is
  /// untouched.
  Uint8List apply(EditableRun run, String replacement) {
    final plan = this.plan(run, replacement);
    if (plan is! EditPatch) {
      throw const UnsupportedPdfStructure(
        technicalDetail: 'the edit was refused',
      );
    }

    final stream = streamContents(_pdf, _index, run.contentObject);
    if (stream == null) {
      throw const UnsupportedPdfStructure(
        technicalDetail: 'the content stream cannot be read',
      );
    }

    final edited = applyTextEdit(stream, run.run, plan);
    final text = latin1.decode(_pdf, allowInvalid: true);

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
    if (_index.usesXrefStream) {
      throw const UnsupportedPdfStructure(
        technicalDetail: 'PDF 1.5+ cross-reference stream',
      );
    }

    final out = <int>[..._pdf];
    if (out.isNotEmpty && out.last != 0x0a) out.add(0x0a);

    // Compressed, because a page's instructions are text and compress well -
    // and because leaving it uncompressed would make an edited document
    // markedly larger than the one it came from.
    final deflated = ZLibCodec(level: 9).encode(edited);
    final offset = out.length;

    out
      ..addAll(
        latin1.encode(
          '${run.contentObject} 0 obj\n'
          '<< /Length ${deflated.length} /Filter /FlateDecode >>\nstream\n',
        ),
      )
      ..addAll(deflated)
      ..addAll(latin1.encode('\nendstream\nendobj\n'));

    final xrefOffset = out.length;
    final info = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text);
    final root = roots.last;

    out.addAll(
      latin1.encode(
        'xref\n'
        '${run.contentObject} 1\n'
        '${offset.toString().padLeft(10, '0')} 00000 n \n'
        'trailer\n'
        '<< /Size ${sizes.last.group(1)} /Root ${root.group(1)} '
        '${root.group(2)} R'
        '${info.isEmpty ? '' : ' /Info ${info.last.group(1)} '
                  '${info.last.group(2)} R'}'
        ' /Prev ${startxref.group(1)} >>\n'
        'startxref\n'
        '$xrefOffset\n'
        '%%EOF\n',
      ),
    );

    return Uint8List.fromList(out);
  }

  /// The objects holding a page's instructions.
  ///
  /// `/Contents` may be one reference or an array of them, and a page whose
  /// text is split across several is common enough that reading only the first
  /// loses most of it.
  List<int> _contentObjects(String page) {
    final array = RegExp(r'/Contents\s*\[([^\]]*)\]').firstMatch(page);
    if (array != null) {
      return RegExp(
        r'(\d+)\s+\d+\s+R',
      ).allMatches(array.group(1)!).map((m) => int.parse(m.group(1)!)).toList();
    }

    final single = RegExp(r'/Contents\s+(\d+)\s+\d+\s+R').firstMatch(page);
    return single == null ? const [] : [int.parse(single.group(1)!)];
  }

  /// How much room there is before the next run on the same line.
  ///
  /// Null when nothing follows it there, in which case a longer replacement
  /// cannot collide with anything and is allowed.
  double? _roomAfter(List<TextRun> runs, int index, PageFont? font) {
    final run = runs[index];
    if (font == null) return null;

    final width = _widthOf(run, font);
    if (width == null) return null;

    for (var i = index + 1; i < runs.length; i++) {
      final next = runs[i];
      // The same line, within a quarter of the text size - which is enough to
      // tell a line apart from the one under it without splitting a line whose
      // baseline shifts for a superscript.
      if ((next.position.y - run.position.y).abs() > run.fontSize / 4) {
        continue;
      }
      if (next.position.x <= run.position.x) continue;

      return next.position.x - (run.position.x + width);
    }

    return null;
  }

  double? _widthOf(TextRun run, PageFont font) {
    final decoder = font.decoder;
    final length = decoder is ToUnicodeDecoder ? decoder.codeLength : 1;
    if (run.bytes.length % length != 0) return null;

    var total = 0.0;
    for (var i = 0; i < run.bytes.length; i += length) {
      var code = 0;
      for (var b = 0; b < length; b++) {
        code = (code << 8) | run.bytes[i + b];
      }

      final width = font.widthOf(code);
      if (width == null) return null;
      total += width;
    }

    return total / 1000 * run.fontSize;
  }
}
