import 'package:folio/domain/annotations/pdf_appearance.dart' show pdfNumber;
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// The geometry keys that hold flat lists of x-y pairs in page space.
///
/// /InkList nests one array per stroke, but the pairs are positional either
/// way, so the same transform applies without knowing the structure.
const _geometryKeys = ['InkList', 'QuadPoints', 'L', 'Vertices'];

/// Maps [p] from the [from] rect into the [to] rect.
PdfPoint transformPoint(
  PdfPoint p, {
  required TextRect from,
  required TextRect to,
}) {
  final fromWidth = from.right - from.left;
  final fromHeight = from.top - from.bottom;
  // A zero-area source would divide by zero and give NaN coordinates, which
  // render nowhere at all.
  if (fromWidth == 0 || fromHeight == 0) return p;

  final scaleX = (to.right - to.left) / fromWidth;
  final scaleY = (to.top - to.bottom) / fromHeight;

  return PdfPoint(
    to.left + (p.x - from.left) * scaleX,
    to.bottom + (p.y - from.bottom) * scaleY,
  );
}

/// Rewrites `/Rect` and every coordinate-pair geometry key in [dict] so they
/// agree after the annotation moves from [from] to [to].
///
/// Rewriting `/Rect` alone would render correctly - a viewer maps the
/// appearance onto the rect - but leave the geometry pointing at the old
/// position, so a later restyle regenerates the appearance where the
/// annotation used to be. They move together or not at all.
String transformAnnotationDict(
  String dict, {
  required TextRect from,
  required TextRect to,
}) {
  if (from.right - from.left == 0 || from.top - from.bottom == 0) return dict;

  var out = dict.replaceFirst(
    RegExp(r'/Rect\s*\[[^\]]*\]'),
    '/Rect [${pdfNumber(to.left)} ${pdfNumber(to.bottom)} '
    '${pdfNumber(to.right)} ${pdfNumber(to.top)}]',
  );

  for (final key in _geometryKeys) {
    final match = RegExp(
      '/$key\\s*(\\[.*?\\])(?=\\s*/|\\s*>>)',
      dotAll: true,
    ).firstMatch(out);
    if (match == null) continue;

    final rewritten = _transformNumbers(match.group(1)!, from: from, to: to);
    out = out.replaceRange(match.start, match.end, '/$key $rewritten');
  }

  return out;
}

/// Rewrites every x-y pair inside a bracketed value, preserving its nesting
/// and any surrounding punctuation.
String _transformNumbers(
  String source, {
  required TextRect from,
  required TextRect to,
}) {
  final numbers = RegExp(r'-?\d+(?:\.\d+)?');
  final values = numbers
      .allMatches(source)
      .map((m) => double.parse(m.group(0)!))
      .toList();

  final moved = <double>[];
  for (var i = 0; i + 1 < values.length; i += 2) {
    final p = transformPoint(
      PdfPoint(values[i], values[i + 1]),
      from: from,
      to: to,
    );
    moved
      ..add(p.x)
      ..add(p.y);
  }
  // An odd trailing number is not part of a pair; leave it as it was.
  if (values.length.isOdd) moved.add(values.last);

  var index = 0;
  return source.replaceAllMapped(numbers, (_) => pdfNumber(moved[index++]));
}

/// The rect [proposed] becomes once its aspect ratio is locked to [original].
///
/// The top-left corner stays put, so the annotation grows away from where the
/// user started the drag rather than jumping.
TextRect lockAspect(TextRect proposed, {required TextRect original}) {
  final ratio =
      (original.right - original.left) / (original.top - original.bottom);
  if (!ratio.isFinite || ratio == 0) return proposed;

  var width = proposed.right - proposed.left;
  var height = proposed.top - proposed.bottom;

  // Fit inside the drag, never outside it.
  if (width / height > ratio) {
    width = height * ratio;
  } else {
    height = width / ratio;
  }

  return TextRect(
    left: proposed.left,
    top: proposed.top,
    right: proposed.left + width,
    bottom: proposed.top - height,
  );
}
