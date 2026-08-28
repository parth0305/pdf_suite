import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/crop/page_crop.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/watermark/page_geometry.dart';

/// The page boxes that must stay inside the crop box, and are not inheritable.
const _containedBoxes = ['BleedBox', 'TrimBox', 'ArtBox'];

/// Trims [margins] off every page, by appending an incremental update.
///
/// Both `/CropBox` and `/MediaBox` are set. Setting only `/CropBox` is what
/// most tools do, and it leaves the crop behind the first time the file is
/// printed or re-imported by something that reads `/MediaBox`.
///
/// This HIDES the margins; it does not delete what was in them. The text is
/// still in the file and still extractable - which is why the sheet says so,
/// and why redaction exists.
Uint8List writeCroppedPages(Uint8List pdf, PageMargins margins) {
  if (margins.isNothing) {
    throw ArgumentError.value(margins, 'margins', 'nothing to trim');
  }

  final text = latin1.decode(pdf, allowInvalid: true);
  final reader = PdfObjectReader.parse(text);
  final index = PdfObjectIndex.parse(text);

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

  final out = <int>[...pdf];
  if (out.isNotEmpty && out.last != 0x0a) out.add(0x0a);

  final offsets = <int, int>{};
  var cropped = 0;

  for (var pageIndex = 0; ; pageIndex++) {
    final page = reader.pageAt(pageIndex);
    if (page == null) break;

    final visible = visibleBoxOf(index, page);
    final box = croppedBox(visible, margins.unrotated(rotationOf(index, page)));
    // A page too small to survive the trim is left as it is. Refusing the
    // whole document because one page is a narrow insert would be worse than
    // cropping the rest.
    if (box == null) continue;

    offsets[page.objectNumber] = out.length;
    out.addAll(
      latin1.encode(
        '${page.objectNumber} 0 obj\n${_withBoxes(page, box)}\nendobj\n',
      ),
    );
    cropped++;
  }

  if (cropped == 0) {
    throw const EmptyDocument();
  }

  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  for (final n in offsets.keys.toList()..sort()) {
    buffer
      ..writeln('$n 1')
      ..writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');

  final info = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  final infoEntry = info.isEmpty
      ? ''
      : ' /Info ${info.last.group(1)} ${info.last.group(2)} R';
  final root = roots.last;

  buffer
    ..writeln(
      '<< /Size ${sizes.last.group(1)} /Root ${root.group(1)} '
      '${root.group(2)} R$infoEntry /Prev ${startxref.group(1)} >>',
    )
    ..writeln('startxref')
    ..writeln('$xrefOffset')
    ..write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}

String _rect(TextRect b) =>
    '[${_n(b.left)} ${_n(b.bottom)} ${_n(b.right)} ${_n(b.top)}]';

String _n(double v) {
  final rounded = (v * 100).roundToDouble() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

/// The page dictionary with every box entry brought inside [box].
String _withBoxes(PdfPageObject page, TextRect box) {
  var body = page.rawDictionary;
  body = body.substring(2, body.length - 2).trim();

  body = _replace(body, 'MediaBox', _rect(box));
  body = _replace(body, 'CropBox', _rect(box));

  for (final name in _containedBoxes) {
    final existing = RegExp(
      '/$name'
      r'\s*\[([^\]]*)\]',
    ).firstMatch(body);
    if (existing == null) continue;

    final numbers = RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(existing.group(1)!)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    if (numbers.length < 4) continue;

    final clipped = intersection(
      TextRect(
        left: numbers[0],
        bottom: numbers[1],
        right: numbers[2],
        top: numbers[3],
      ),
      box,
    );
    // A production box with no overlap left is dropped: keeping one outside
    // the crop box is exactly the invalidity this loop exists to prevent.
    body = body.replaceRange(
      existing.start,
      existing.end,
      clipped == null ? '' : '/$name ${_rect(clipped)}',
    );
  }

  return '<< $body >>';
}

String _replace(String body, String name, String value) {
  final existing = RegExp(
    '/$name'
    r'\s*\[[^\]]*\]',
  ).firstMatch(body);
  return existing == null
      ? '$body /$name $value'
      : body.replaceRange(existing.start, existing.end, '/$name $value');
}
