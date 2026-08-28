import 'package:folio/domain/annotations/pdf_appearance.dart' show pdfString;
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/forms/form_field.dart';

/// The font a generated appearance uses when the field names none.
const fieldFontName = 'Helv';

/// Padding between the field's border and its text, in points. Two is what
/// Acrobat uses, and a filled field that sits flush against its own box reads
/// as broken even when the value is right.
const _padding = 2.0;

/// A field's `/DA` broken into the parts an appearance needs.
///
/// `/DA` is a fragment of a content stream - `/Helv 12 Tf 0 g` - rather than a
/// structured value. It is reused verbatim so a filled field matches the ones
/// around it; only a size of zero, which means "fit it", has to be resolved.
class DefaultAppearance {
  const DefaultAppearance({
    required this.fontName,
    required this.size,
    required this.operators,
  });

  final String fontName;

  /// Zero means auto-size, per ISO 32000-1 §12.7.3.3.
  final double size;

  /// The whole `/DA` string, font operator included.
  final String operators;

  static DefaultAppearance parse(String? da) {
    final text = da ?? '/$fieldFontName 0 Tf 0 g';
    final font = RegExp(r'/([^\s/]+)\s+(-?[\d.]+)\s+Tf').firstMatch(text);

    return DefaultAppearance(
      fontName: font?.group(1) ?? fieldFontName,
      size: double.tryParse(font?.group(2) ?? '') ?? 0,
      operators: text,
    );
  }

  /// The size to draw at inside a box [height] tall.
  ///
  /// An auto-sized field is not a licence to pick anything: the text has to
  /// fit the box with its padding, and 12 point is the size a form that says
  /// nothing expects.
  double sizeFor(double height) {
    if (size > 0) return size;

    final fits = height - _padding * 2;
    return fits < 12 ? (fits < 4 ? 4 : fits) : 12;
  }

  /// [operators] with an auto size replaced by a real one, so the appearance
  /// stream never says `0 Tf`.
  String resolvedFor(double height) => size > 0
      ? operators
      : operators.replaceFirst(
          RegExp(r'/([^\s/]+)\s+-?[\d.]+\s+Tf'),
          '/$fontName ${_number(sizeFor(height))} Tf',
        );
}

/// The appearance stream for a text or choice field showing [value].
///
/// Wrapped in `/Tx BMC ... EMC` as ISO 32000-1 §12.7.3.3 requires, and clipped
/// to the field's box: a value longer than the field must be cut off by the
/// box rather than run across the page.
String fieldAppearanceStream({
  required String value,
  required TextRect rect,
  required DefaultAppearance appearance,
  int quadding = 0,
  bool multiline = false,
}) {
  final width = rect.width;
  final height = rect.height;
  final size = appearance.sizeFor(height);
  final da = appearance.resolvedFor(height);

  final buffer = StringBuffer()
    ..writeln('/Tx BMC')
    ..writeln('q')
    ..writeln(
      '${_number(0)} ${_number(0)} ${_number(width)} '
      '${_number(height)} re W n',
    )
    ..writeln('BT')
    ..writeln(da);

  final lines = multiline ? value.split('\n') : [value.replaceAll('\n', ' ')];

  // The first baseline sits one line down from the top for a multiline field,
  // and centred for a single-line one - which is what makes a filled field
  // look level with its label rather than sitting on the border.
  var y = multiline
      ? height - _padding - size
      : (height - size * 0.72) / 2 + size * 0.02;

  for (final line in lines) {
    buffer
      ..writeln(
        '1 0 0 1 ${_number(_x(line, size, width, quadding))} '
        '${_number(y)} Tm',
      )
      ..writeln('${pdfString(line)} Tj');
    y -= size * 1.15;
  }

  buffer
    ..writeln('ET')
    ..writeln('Q')
    ..write('EMC\n');

  return buffer.toString();
}

/// Where a line starts, for the field's `/Q` alignment.
///
/// Width comes from Helvetica's average advance rather than real metrics.
/// Centring by an estimate is visibly better than not centring at all, and
/// the alternative is embedding a font metrics table for one alignment.
double _x(String line, double size, double width, int quadding) {
  if (quadding == 0) return _padding;

  final estimated = line.length * size * 0.5;
  return switch (quadding) {
    1 =>
      (width - estimated) / 2 < _padding ? _padding : (width - estimated) / 2,
    2 =>
      width - _padding - estimated < _padding
          ? _padding
          : width - _padding - estimated,
    _ => _padding,
  };
}

/// The value to draw for [field] given the [value] chosen.
///
/// A choice field stores an export value and displays a label. Drawing the
/// export value puts `IN` in a box where the person picked `India`.
String displayedValue(FormField field, String value) {
  if (field.kind != FormFieldKind.choice) return value;

  final index = field.exports.indexOf(value);
  return index >= 0 && index < field.options.length
      ? field.options[index]
      : value;
}

String _number(double v) {
  final rounded = (v * 100).roundToDouble() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
