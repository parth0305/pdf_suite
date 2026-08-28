import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfStreamBody, pdfString;
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/forms/field_appearance.dart';
import 'package:folio/domain/forms/form_field.dart';
import 'package:folio/domain/forms/pdf_form_reader.dart';
import 'package:folio/domain/forms/pdf_value.dart';

/// Fills form fields, by appending an incremental update.
///
/// Appearances are GENERATED rather than left to the reader. Setting
/// `/NeedAppearances true` asks whoever opens the file to draw the value:
/// readers that honour it disagree about how, readers that ignore it show a
/// blank field, and printing frequently shows neither. Folio draws the value
/// itself, so it is there in every reader and on paper.
///
/// [values] is keyed by fully qualified field name. A null value clears the
/// field. Names that are not in the document, and fields that cannot be
/// filled, are ignored rather than silently invented.
Uint8List writeFilledForm(Uint8List pdf, Map<String, String?> values) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final reader = PdfObjectReader.parse(text);
  final index = PdfObjectIndex.parse(text);
  final form = PdfFormReader.parse(text);

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

  var nextObj = int.parse(sizes.last.group(1)!);
  final out = <int>[...pdf];
  if (out.isNotEmpty && out.last != 0x0a) out.add(0x0a);

  final offsets = <int, int>{};
  void emit(int number, String body) {
    offsets[number] = out.length;
    out.addAll(latin1.encode('$number 0 obj\n$body\nendobj\n'));
  }

  int emitStream(String dict, String content) {
    final number = nextObj++;
    final body = pdfStreamBody(content);
    offsets[number] = out.length;
    out
      ..addAll(
        latin1.encode(
          '$number 0 obj\n<< $dict /Length ${body.bytes.length}'
          '${body.filter} >>\nstream\n',
        ),
      )
      ..addAll(body.bytes)
      ..addAll(latin1.encode('\nendstream\nendobj\n'));
    return number;
  }

  // Field and widget are usually the SAME object, so edits are collected per
  // object and applied once. Emitting the object twice would leave the first
  // version superseded and half the edits lost.
  final edits = <int, Map<String, String>>{};
  void editObject(int number, String key, String value) =>
      (edits[number] ??= {})[key] = value;

  var fontNum = 0;
  var filled = 0;

  for (final field in form.fields) {
    if (!values.containsKey(field.name) || !field.isFillable) continue;

    final value = values[field.name];
    filled++;

    switch (field.kind) {
      case FormFieldKind.checkBox:
      case FormFieldKind.radio:
        // The chosen state names itself. Anything else - including no value -
        // is /Off, which is the one state name the specification does fix.
        final chosen = value == null || value.isEmpty ? 'Off' : value;
        editObject(field.objectNumber, 'V', '/$chosen');

        for (final widget in field.widgets) {
          editObject(
            widget.objectNumber,
            'AS',
            widget.onState == chosen ? '/$chosen' : '/Off',
          );
        }

      case FormFieldKind.text:
      case FormFieldKind.choice:
        if (value == null || value.isEmpty) {
          editObject(field.objectNumber, 'V', '()');
        } else {
          editObject(field.objectNumber, 'V', pdfString(value));
        }

        if (fontNum == 0) {
          fontNum = nextObj++;
          emit(
            fontNum,
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding /WinAnsiEncoding >>',
          );
        }

        final appearance = DefaultAppearance.parse(field.defaultAppearance);
        for (final widget in field.widgets) {
          final quadding = int.tryParse(
            RegExp(r'/Q\s+(\d+)')
                    .firstMatch(index.bodyOf(widget.objectNumber) ?? '')
                    ?.group(1) ??
                '',
          );

          final stream = emitStream(
            '/Type /XObject /Subtype /Form '
            '/BBox [0 0 ${_n(widget.rect.width)} ${_n(widget.rect.height)}] '
            '/Resources << /Font << /${appearance.fontName} $fontNum 0 R >> >>',
            fieldAppearanceStream(
              value: value == null ? '' : displayedValue(field, value),
              rect: widget.rect,
              appearance: appearance,
              quadding: quadding ?? 0,
              multiline: field.isMultiline,
            ),
          );

          editObject(widget.objectNumber, 'AP', '<< /N $stream 0 R >>');
        }

      case FormFieldKind.signature:
      case FormFieldKind.pushButton:
        break;
    }
  }

  // Covers both "this document has no form" and "none of these names is a
  // field in it". A separate guard for the first said the same thing twice.
  if (filled == 0) {
    throw const NoFormFields();
  }

  for (final entry in edits.entries) {
    final body = index.bodyOf(entry.key);
    if (body == null) continue;

    var dict = body;
    for (final edit in entry.value.entries) {
      dict = withEntry(dict, edit.key, edit.value);
    }
    emit(entry.key, dict);
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
      '<< /Size $nextObj /Root ${root.group(1)} ${root.group(2)} R'
      '$infoEntry /Prev ${startxref.group(1)} >>',
    )
    ..writeln('startxref')
    ..writeln('$xrefOffset')
    ..write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}

String _n(double v) {
  final rounded = (v * 100).roundToDouble() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
