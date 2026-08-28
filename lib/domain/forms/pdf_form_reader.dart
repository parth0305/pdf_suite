import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/forms/form_field.dart';
import 'package:folio/domain/forms/pdf_value.dart';

/// How deep a field tree may go before it is treated as damaged. Real forms
/// nest two or three levels; a cycle nests forever.
const _maxDepth = 16;

/// Reads a document's AcroForm.
///
/// A form is a TREE. `/FT`, `/Ff`, `/V` and `/DA` are inheritable, a field's
/// name is the dotted path from the root, and the object that holds a value is
/// often not the object drawn on the page. Reading it as a flat list of
/// annotations produces something that looks like a form and fills in wrong.
class PdfFormReader {
  PdfFormReader._(this.fields);

  final List<FormField> fields;

  bool get hasForm => fields.isNotEmpty;

  static PdfFormReader parse(String pdfText) {
    final index = PdfObjectIndex.parse(pdfText);
    final root = RegExp(r'/Root\s+(\d+)\s+\d+\s+R').allMatches(pdfText);
    if (root.isEmpty) return PdfFormReader._(const []);

    final catalog = index.bodyOf(int.parse(root.last.group(1)!));
    if (catalog == null) return PdfFormReader._(const []);

    final acroForm = _dictionaryFor(index, catalog, '/AcroForm');
    if (acroForm == null) return PdfFormReader._(const []);

    // An XFA document's fields live in an XML payload; the PDF pages are a
    // "please open this in Acrobat" placeholder. Filling the AcroForm shell
    // would produce a document whose two halves disagree.
    if (RegExp(r'/XFA(?![A-Za-z])').hasMatch(acroForm)) {
      throw const UnsupportedPdfStructure(technicalDetail: 'XFA form');
    }

    final pageOf = _widgetPages(pdfText);
    final defaultAppearance = readValue(acroForm, 'DA');
    final fields = <FormField>[];

    for (final ref in _references(acroForm, 'Fields')) {
      _walk(
        index: index,
        objectNumber: ref,
        prefix: '',
        ancestors: const [],
        inherited: (
          type: null,
          flags: null,
          value: null,
          appearance: defaultAppearance,
          maxLength: null,
        ),
        pageOf: pageOf,
        depth: 0,
        out: fields,
      );
    }

    return PdfFormReader._(List.unmodifiable(fields));
  }
}

typedef _Inherited = ({
  String? type,
  int? flags,
  String? value,
  String? appearance,
  int? maxLength,
});

void _walk({
  required PdfObjectIndex index,
  required int objectNumber,
  required String prefix,
  required List<int> ancestors,
  required _Inherited inherited,
  required Map<int, int> pageOf,
  required int depth,
  required List<FormField> out,
}) {
  if (depth > _maxDepth) return;

  final dict = index.bodyOf(objectNumber);
  if (dict == null) return;

  final partial = readValue(dict, 'T');
  final name = partial == null
      ? prefix
      : prefix.isEmpty
      ? partial
      : '$prefix.$partial';

  final here = (
    type: RegExp(r'/FT\s*/(\w+)').firstMatch(dict)?.group(1) ?? inherited.type,
    flags:
        int.tryParse(
          RegExp(r'/Ff\s+(-?\d+)').firstMatch(dict)?.group(1) ?? '',
        ) ??
        inherited.flags,
    value: readValue(dict, 'V') ?? inherited.value,
    appearance: readValue(dict, 'DA') ?? inherited.appearance,
    maxLength:
        int.tryParse(
          RegExp(r'/MaxLen\s+(\d+)').firstMatch(dict)?.group(1) ?? '',
        ) ??
        inherited.maxLength,
  );

  final kids = _references(dict, 'Kids');
  // Kids that name themselves are child FIELDS; kids that do not are this
  // field's widgets. A radio group is the everyday case: several unnamed kids,
  // one value, one field.
  final childFields = kids
      .where((k) => readValue(index.bodyOf(k) ?? '', 'T') != null)
      .toList();

  if (childFields.isNotEmpty) {
    for (final kid in childFields) {
      _walk(
        index: index,
        objectNumber: kid,
        prefix: name,
        ancestors: [...ancestors, objectNumber],
        inherited: here,
        pageOf: pageOf,
        depth: depth + 1,
        out: out,
      );
    }
    return;
  }

  final kind = kindOf(here.type, here.flags ?? 0);
  final widgetNumbers = kids.isEmpty ? [objectNumber] : kids;
  final widgets = <FormWidget>[];
  final states = <String>[];

  for (final number in widgetNumbers) {
    final widget = index.bodyOf(number);
    if (widget == null) continue;

    final onState = _onStateOf(widget);
    if (onState != null) states.add(onState);

    widgets.add(
      FormWidget(
        objectNumber: number,
        pageIndex: pageOf[number] ?? 0,
        rect:
            _rectIn(widget) ??
            const TextRect(left: 0, top: 0, right: 0, bottom: 0),
        onState: onState,
      ),
    );
  }

  out.add(
    FormField(
      name: name,
      kind: kind,
      objectNumber: objectNumber,
      widgets: widgets,
      value: here.value,
      options: kind == FormFieldKind.choice ? readOptions(dict) : states,
      exports: kind == FormFieldKind.choice ? exportValues(dict) : states,
      flags: here.flags ?? 0,
      maxLength: here.maxLength,
      defaultAppearance: here.appearance,
      ancestors: ancestors,
    ),
  );
}

/// The `/AP /N` state that means "on": every key of the appearance dictionary
/// except `/Off`.
///
/// A checkbox's on-state is named by the document, not by the specification -
/// `/Yes` is a convention, `/1` and `/On` are just as legal - so assuming
/// `/Yes` gives a box that cannot be ticked in half the forms in the world.
String? _onStateOf(String widget) {
  final ap = RegExp(r'/AP\s*<<').firstMatch(widget);
  if (ap == null) return null;

  final normal = RegExp(r'/N\s*<<').firstMatch(widget.substring(ap.end));
  if (normal == null) return null;

  final start = ap.end + normal.end;
  final end = PdfObjectIndex.matchingClose(widget, start - 2);

  for (final key in RegExp(
    r'/([^\s/<>\[\]]+)\s+\d+\s+\d+\s+R',
  ).allMatches(widget.substring(start, end.clamp(start, widget.length)))) {
    if (key.group(1) != 'Off') return key.group(1);
  }
  return null;
}

/// Which page each widget object is drawn on.
///
/// The widget does not say; the page's `/Annots` does. A widget whose page
/// cannot be found would otherwise be filled invisibly on page one.
Map<int, int> _widgetPages(String pdfText) {
  final pages = PdfObjectReader.parse(pdfText);
  final out = <int, int>{};

  for (var pageIndex = 0; ; pageIndex++) {
    final page = pages.pageAt(pageIndex);
    if (page == null) break;

    for (final ref in page.existingAnnotRefs) {
      out[int.parse(ref.split(' ').first)] = pageIndex;
    }
  }

  return out;
}

/// The dictionary [key] points at, whether it is written inline or as a
/// reference. Both occur, and only handling one means half of all forms are
/// invisible.
String? _dictionaryFor(PdfObjectIndex index, String dict, String key) {
  final reference = RegExp(
    '$key'
    r'\s+(\d+)\s+\d+\s+R',
  ).firstMatch(dict);
  if (reference != null) return index.bodyOf(int.parse(reference.group(1)!));

  final inline = RegExp(
    '$key'
    r'\s*<<',
  ).firstMatch(dict);
  if (inline == null) return null;

  final close = PdfObjectIndex.matchingClose(dict, inline.end - 2);
  return dict.substring(inline.end - 2, (close + 2).clamp(0, dict.length));
}

List<int> _references(String dict, String key) {
  final at = RegExp(
    '/$key'
    r'\s*\[',
  ).firstMatch(dict);
  if (at == null) return const [];

  final close = dict.indexOf(']', at.end);
  if (close == -1) return const [];

  return RegExp(r'(\d+)\s+\d+\s+R')
      .allMatches(dict.substring(at.end, close))
      .map((m) => int.parse(m.group(1)!))
      .toList();
}

TextRect? _rectIn(String dict) {
  final match = RegExp(r'/Rect\s*\[([^\]]*)\]').firstMatch(dict);
  if (match == null) return null;

  final n = RegExp(
    r'-?\d+(?:\.\d+)?',
  ).allMatches(match.group(1)!).map((m) => double.parse(m.group(0)!)).toList();
  if (n.length < 4) return null;

  return TextRect(
    left: n[0] < n[2] ? n[0] : n[2],
    right: n[0] < n[2] ? n[2] : n[0],
    bottom: n[1] < n[3] ? n[1] : n[3],
    top: n[1] < n[3] ? n[3] : n[1],
  );
}
