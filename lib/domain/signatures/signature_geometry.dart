import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/saved_signature.dart';

/// Maps captured strokes into a unit box, y-up, and reports the aspect ratio
/// they were drawn at.
({List<List<PdfPoint>> strokes, double aspectRatio}) normaliseStrokes(
  List<List<PdfPoint>> captured,
) {
  final all = captured.expand((s) => s).toList();
  if (all.isEmpty) {
    return (strokes: const [], aspectRatio: 1);
  }

  var left = all.first.x;
  var right = all.first.x;
  var bottom = all.first.y;
  var top = all.first.y;
  for (final p in all) {
    if (p.x < left) left = p.x;
    if (p.x > right) right = p.x;
    if (p.y < bottom) bottom = p.y;
    if (p.y > top) top = p.y;
  }

  // A perfectly horizontal stroke has zero height. Dividing by it would give
  // NaN coordinates and an annotation that renders nowhere.
  final width = right - left;
  final height = top - bottom;
  final safeWidth = width == 0 ? 1.0 : width;
  final safeHeight = height == 0 ? 1.0 : height;

  return (
    strokes: [
      for (final stroke in captured)
        [
          for (final p in stroke)
            PdfPoint((p.x - left) / safeWidth, (p.y - bottom) / safeHeight),
        ],
    ],
    aspectRatio: safeWidth / safeHeight,
  );
}

/// Fits [signature] inside [box] preserving its aspect ratio, centred.
List<List<PdfPoint>> placeSignature(
  SavedSignature signature, {
  required TextRect box,
}) {
  final boxWidth = box.right - box.left;
  final boxHeight = box.top - box.bottom;

  // Fit, never fill: whichever dimension runs out first sets the scale.
  var width = boxWidth;
  var height = width / signature.aspectRatio;
  if (height > boxHeight) {
    height = boxHeight;
    width = height * signature.aspectRatio;
  }

  final offsetX = box.left + (boxWidth - width) / 2;
  final offsetY = box.bottom + (boxHeight - height) / 2;

  return [
    for (final stroke in signature.strokes)
      [
        for (final p in stroke)
          PdfPoint(offsetX + p.x * width, offsetY + p.y * height),
      ],
  ];
}
