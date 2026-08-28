import 'package:folio/domain/engine/pdf_types.dart';

/// What flattening should do with one annotation.
enum FlattenDecision {
  /// Paint its appearance into the page, then remove it.
  draw,

  /// Remove it without painting anything.
  drop,

  /// Leave it exactly as it is.
  keep,
}

/// ISO 32000-1 Table 165: bit 2 is Hidden, bit 6 is NoView.
const _hidden = 2;
const _noView = 32;

/// How to flatten the annotation whose dictionary is [dict].
///
/// [appearance] is the object number of its normal appearance, or null when it
/// has none that can be painted.
FlattenDecision flattenDecisionFor(String dict, {required int? appearance}) {
  final subtype = RegExp(r'/Subtype\s*/(\w+)').firstMatch(dict)?.group(1);

  // A popup is the note's open window, not the note. It is never printed, and
  // painting one would stamp a floating text box onto the page.
  if (subtype == 'Popup') return FlattenDecision.drop;

  final flags = int.tryParse(
    RegExp(r'/F\s+(\d+)').firstMatch(dict)?.group(1) ?? '',
  );
  if (flags != null && (flags & (_hidden | _noView)) != 0) {
    return FlattenDecision.drop;
  }

  // A link has no appearance worth painting and everything worth keeping.
  // Flattening one leaves a rectangle that no longer goes anywhere.
  if (subtype == 'Link') return FlattenDecision.keep;

  // No appearance means nothing to paint. Removing it anyway would delete
  // whatever it held - a form field's value, most often - and call that
  // flattening.
  return appearance == null ? FlattenDecision.keep : FlattenDecision.draw;
}

/// The object number of the annotation's normal appearance stream.
///
/// `/AP /N` is either a reference to one stream, or a dictionary of states
/// among which `/AS` names the current one. A checkbox is the everyday case:
/// its `/N` holds both `/Off` and `/Yes`.
int? normalAppearanceOf(String dict) {
  final ap = RegExp(r'/AP\s*<<').firstMatch(dict);
  if (ap == null) return null;

  final direct = RegExp(
    r'/N\s+(\d+)\s+\d+\s+R',
  ).firstMatch(dict.substring(ap.end));
  if (direct != null) return int.parse(direct.group(1)!);

  final state = RegExp(r'/AS\s*/(\w+)').firstMatch(dict)?.group(1);
  if (state == null) return null;

  final states = RegExp(r'/N\s*<<').firstMatch(dict.substring(ap.end));
  if (states == null) return null;

  final chosen = RegExp(
    '/$state'
    r'\s+(\d+)\s+\d+\s+R',
  ).firstMatch(dict.substring(ap.end + states.end));
  return chosen == null ? null : int.parse(chosen.group(1)!);
}

/// The `cm` operands that place an appearance form inside [rect].
///
/// ISO 32000-1 §12.5.5: the appearance's `/BBox` is transformed by its
/// `/Matrix`, the bounding box of THAT is fitted to `/Rect`, and the result is
/// what the page concatenates. `Do` applies the form's own matrix afterwards,
/// so it must not be applied twice here.
///
/// Skipping the matrix step places a rotated appearance - every stamp turned
/// on the page - at the wrong size and offset.
List<double> appearanceTransform({
  required TextRect rect,
  required TextRect bbox,
  List<double> matrix = const [1, 0, 0, 1, 0, 0],
}) {
  final xs = <double>[];
  final ys = <double>[];

  for (final corner in [
    [bbox.left, bbox.bottom],
    [bbox.right, bbox.bottom],
    [bbox.right, bbox.top],
    [bbox.left, bbox.top],
  ]) {
    xs.add(matrix[0] * corner[0] + matrix[2] * corner[1] + matrix[4]);
    ys.add(matrix[1] * corner[0] + matrix[3] * corner[1] + matrix[5]);
  }

  final left = xs.reduce((a, b) => a < b ? a : b);
  final right = xs.reduce((a, b) => a > b ? a : b);
  final bottom = ys.reduce((a, b) => a < b ? a : b);
  final top = ys.reduce((a, b) => a > b ? a : b);

  final target = normalised(rect);
  // A degenerate box scales by one rather than by infinity. ISO 32000-1 says
  // such an appearance should not be painted at all; leaving it unscaled is
  // the recoverable half of that.
  final sx = right - left == 0 ? 1.0 : target.width / (right - left);
  final sy = top - bottom == 0 ? 1.0 : target.height / (top - bottom);

  return [sx, 0, 0, sy, target.left - left * sx, target.bottom - bottom * sy];
}

/// [rect] with its corners the right way round.
///
/// `/Rect` is written by other software, and plenty of it emits the corners in
/// the order they were dragged rather than lower-left first.
TextRect normalised(TextRect rect) => TextRect(
  left: rect.left < rect.right ? rect.left : rect.right,
  right: rect.left < rect.right ? rect.right : rect.left,
  bottom: rect.bottom < rect.top ? rect.bottom : rect.top,
  top: rect.bottom < rect.top ? rect.top : rect.bottom,
);

/// One appearance, placed on the page.
class PlacedAppearance {
  const PlacedAppearance({required this.resourceName, required this.transform});

  final String resourceName;
  final List<double> transform;
}

/// The content stream that paints [placed], in the order given.
///
/// Each is wrapped in `q`/`Q` so one appearance's transform cannot leak into
/// the next, and none of them into the page's own content.
String flattenContentStream(List<PlacedAppearance> placed) {
  final buffer = StringBuffer();

  for (final one in placed) {
    buffer
      ..write('q ')
      ..write(one.transform.map(_number).join(' '))
      ..write(' cm /')
      ..write(one.resourceName)
      ..writeln(' Do Q');
  }

  return buffer.toString();
}

String _number(double v) {
  final rounded = (v * 10000).roundToDouble() / 10000;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
