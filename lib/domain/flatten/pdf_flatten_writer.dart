import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfStreamBody;
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/flatten/annotation_appearance.dart';
import 'package:folio/domain/forms/pdf_form_reader.dart';

/// Paints every annotation into the page it sits on, by appending an
/// incremental update.
///
/// Flattening is what makes a filled form, a signature or a stamp part of the
/// page rather than something the next reader can drag off it. The appearance
/// streams are REUSED where they are - a form XObject is already exactly what
/// the page needs - so nothing is re-encoded and nothing is re-rendered.
///
/// Annotations that cannot be painted are left alone rather than deleted. A
/// field whose value lives only in the annotation would otherwise disappear,
/// which looks like flattening right up until someone needs the value.
Uint8List writeFlattened(Uint8List pdf) {
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

  var nextObj = int.parse(sizes.last.group(1)!);
  final out = <int>[...pdf];
  if (out.isNotEmpty && out.last != 0x0a) out.add(0x0a);

  final offsets = <int, int>{};
  void emit(int number, String body) {
    offsets[number] = out.length;
    out.addAll(latin1.encode('$number 0 obj\n$body\nendobj\n'));
  }

  var flattened = 0;
  final keptWidgets = <int>{};

  for (var pageIndex = 0; ; pageIndex++) {
    final page = reader.pageAt(pageIndex);
    if (page == null) break;
    if (page.existingAnnotRefs.isEmpty) continue;

    final placed = <PlacedAppearance>[];
    final resources = <String, int>{};
    final kept = <String>[];

    for (final ref in page.existingAnnotRefs) {
      final number = int.parse(ref.split(' ').first);
      final annot = index.bodyOf(number);
      // A reference to an object that is not there is left in place. It is
      // already broken; deleting it would only hide that.
      if (annot == null) {
        kept.add(ref);
        keptWidgets.add(number);
        continue;
      }

      final appearance = normalAppearanceOf(annot);
      switch (flattenDecisionFor(annot, appearance: appearance)) {
        case FlattenDecision.keep:
          kept.add(ref);
          keptWidgets.add(number);
        case FlattenDecision.drop:
          break;
        case FlattenDecision.draw:
          final form = index.bodyOf(appearance!);
          final rect = _rectIn(annot, '/Rect');
          final bbox = form == null ? null : _rectIn(form, '/BBox');
          // Without a /BBox there is no way to know what part of the form to
          // fit into /Rect, and guessing would paint it at the wrong scale.
          if (rect == null || bbox == null) {
            kept.add(ref);
            keptWidgets.add(number);
            continue;
          }

          final name = 'FlA${placed.length}';
          resources[name] = appearance;
          placed.add(
            PlacedAppearance(
              resourceName: name,
              transform: appearanceTransform(
                rect: rect,
                bbox: bbox,
                matrix: _matrixIn(form!),
              ),
            ),
          );
      }
    }

    if (placed.isEmpty && kept.length == page.existingAnnotRefs.length) {
      continue;
    }

    var contentNum = 0;
    if (placed.isNotEmpty) {
      contentNum = nextObj++;
      final body = pdfStreamBody(flattenContentStream(placed));
      offsets[contentNum] = out.length;
      out
        ..addAll(
          latin1.encode(
            '$contentNum 0 obj\n'
            '<< /Length ${body.bytes.length}${body.filter} >>\nstream\n',
          ),
        )
        ..addAll(body.bytes)
        ..addAll(latin1.encode('\nendstream\nendobj\n'));
    }

    emit(page.objectNumber, _flattenedPage(page, contentNum, resources, kept));
    flattened += placed.length;
  }

  if (flattened == 0) {
    throw const NothingToFlatten();
  }

  // A form whose fields are now page content must stop being a form, or a
  // viewer will draw its own empty fields straight back over them - and a
  // document that still LISTS a field nobody can see is a form on paper only.
  final root = roots.last;
  final catalogNumber = int.parse(root.group(1)!);
  final catalog = index.bodyOf(catalogNumber);
  if (catalog != null && catalog.contains('/AcroForm')) {
    _rewriteForm(
      text: text,
      index: index,
      catalog: catalog,
      catalogNumber: catalogNumber,
      keptWidgets: keptWidgets,
      emit: emit,
    );
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

TextRect? _rectIn(String dict, String key) {
  final match = RegExp(
    '$key'
    r'\s*\[([^\]]*)\]',
  ).firstMatch(dict);
  if (match == null) return null;

  final n = RegExp(
    r'-?\d+(?:\.\d+)?',
  ).allMatches(match.group(1)!).map((m) => double.parse(m.group(0)!)).toList();
  if (n.length < 4) return null;

  return TextRect(left: n[0], bottom: n[1], right: n[2], top: n[3]);
}

List<double> _matrixIn(String dict) {
  final match = RegExp(r'/Matrix\s*\[([^\]]*)\]').firstMatch(dict);
  if (match == null) return const [1, 0, 0, 1, 0, 0];

  final n = RegExp(
    r'-?\d+(?:\.\d+)?',
  ).allMatches(match.group(1)!).map((m) => double.parse(m.group(0)!)).toList();
  return n.length < 6 ? const [1, 0, 0, 1, 0, 0] : n;
}

/// The page with the painted appearances in `/Contents`, their forms in
/// `/Resources`, and only the surviving annotations in `/Annots`.
String _flattenedPage(
  PdfPageObject page,
  int contentNum,
  Map<String, int> resources,
  List<String> kept,
) {
  var body = page.rawDictionary;
  body = body.substring(2, body.length - 2).trim();

  if (contentNum != 0) {
    final contents = RegExp(
      r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)',
    ).firstMatch(body);
    final existing = contents == null
        ? ''
        : contents.group(1)!.startsWith('[')
        ? contents.group(1)!.substring(1, contents.group(1)!.length - 1).trim()
        : contents.group(1)!.trim();

    // Appended, so the appearances land ON the page's own content rather than
    // under it - which is where the annotations were.
    final merged = existing.isEmpty
        ? '/Contents [$contentNum 0 R]'
        : '/Contents [$existing $contentNum 0 R]';

    body = contents == null
        ? '$body $merged'
        : body.replaceRange(contents.start, contents.end, merged);
  }

  final annots = kept.isEmpty ? '' : '/Annots [${kept.join(' ')}]';
  body = body.replaceFirst(RegExp(r'/Annots\s*\[[^\]]*\]'), annots);

  if (resources.isEmpty) return '<< $body >>';

  final entries = resources.entries
      .map((e) => '/${e.key} ${e.value} 0 R')
      .join(' ');

  // Inserted after the opening `<<` of whichever dictionary is already there,
  // which needs no index arithmetic - the same approach the OCR and
  // image-watermark writers settled on after getting the closing brace wrong.
  final xobjects = RegExp(r'/XObject\s*<<').firstMatch(body);
  if (xobjects != null) {
    return '<< ${body.replaceRange(xobjects.end, xobjects.end, ' $entries')} >>';
  }

  final res = RegExp(r'/Resources\s*<<').firstMatch(body);
  if (res != null) {
    return '<< ${body.replaceRange(res.end, res.end, ' /XObject << $entries >>')} >>';
  }

  return '<< $body /Resources << /XObject << $entries >> >> >>';
}

/// Brings `/AcroForm /Fields` down to the fields that still have a widget on
/// a page, and removes `/AcroForm` entirely when none of them do.
///
/// A field whose every widget was painted into the page is not a field any
/// more. Leaving it listed keeps the document a form, and a reader that
/// regenerates appearances will draw an empty box over the flattened value.
void _rewriteForm({
  required String text,
  required PdfObjectIndex index,
  required String catalog,
  required int catalogNumber,
  required Set<int> keptWidgets,
  required void Function(int number, String body) emit,
}) {
  // Nothing survived anywhere, so there is no form left to describe - and
  // this holds even when the /AcroForm dictionary itself cannot be read.
  if (keptWidgets.isEmpty) {
    emit(catalogNumber, _withoutAcroForm(catalog));
    return;
  }

  final form = PdfFormReader.parse(text);

  bool survives(int fieldNumber) => form.fields
      .where(
        (f) =>
            f.objectNumber == fieldNumber || f.ancestors.contains(fieldNumber),
      )
      .any((f) => f.widgets.any((w) => keptWidgets.contains(w.objectNumber)));

  final reference = RegExp(r'/AcroForm\s+(\d+)\s+\d+\s+R').firstMatch(catalog);
  final dict = reference != null
      ? index.bodyOf(int.parse(reference.group(1)!))
      : _inlineForm(catalog);
  if (dict == null) return;

  final fields = RegExp(r'/Fields\s*\[([^\]]*)\]').firstMatch(dict);
  final surviving = fields == null
      ? <String>[]
      : RegExp(r'(\d+)\s+\d+\s+R')
            .allMatches(fields.group(1)!)
            .where((m) => survives(int.parse(m.group(1)!)))
            .map((m) => m.group(0)!)
            .toList();

  if (surviving.isEmpty) {
    emit(catalogNumber, _withoutAcroForm(catalog));
    return;
  }
  // Nothing was pruned, so the catalog does not need rewriting.
  final before = RegExp(r'\d+\s+\d+\s+R').allMatches(fields!.group(1)!).length;
  if (surviving.length == before) return;

  final updated = dict.replaceRange(
    fields.start,
    fields.end,
    '/Fields [${surviving.join(' ')}]',
  );

  if (reference != null) {
    emit(int.parse(reference.group(1)!), updated);
  } else {
    emit(catalogNumber, catalog.replaceFirst(dict, updated));
  }
}

String? _inlineForm(String catalog) {
  final at = RegExp(r'/AcroForm\s*<<').firstMatch(catalog);
  if (at == null) return null;

  final close = PdfObjectIndex.matchingClose(catalog, at.end - 2);
  return catalog.substring(at.end - 2, (close + 2).clamp(0, catalog.length));
}

/// The catalog with `/AcroForm` removed, reference or dictionary.
String _withoutAcroForm(String catalog) {
  final direct = RegExp(r'/AcroForm\s+\d+\s+\d+\s+R').firstMatch(catalog);
  if (direct != null) {
    return catalog.replaceRange(direct.start, direct.end, '');
  }

  final inline = RegExp(r'/AcroForm\s*<<').firstMatch(catalog);
  if (inline == null) return catalog;

  final close = PdfObjectIndex.matchingClose(catalog, inline.end - 2);
  return catalog.replaceRange(inline.start, close + 2, '');
}
