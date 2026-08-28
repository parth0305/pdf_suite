import 'dart:typed_data';

import 'package:folio/domain/engine/pdf_types.dart';

/// ISO 32000-1 §14.11.2: a page may not be smaller than 3 units square. It is
/// the smallest refusal that is not invented.
const _minimumPageSize = 3.0;

/// How much to trim from each side of a page, in PDF points.
///
/// These are the sides the READER sees. A rotated page's displayed top is not
/// its `/MediaBox` top, and [unrotated] is what reconciles the two.
class PageMargins {
  const PageMargins({
    this.left = 0,
    this.bottom = 0,
    this.right = 0,
    this.top = 0,
  });

  final double left;
  final double bottom;
  final double right;
  final double top;

  bool get isNothing => left <= 0 && bottom <= 0 && right <= 0 && top <= 0;

  /// The same trim expressed in the page's own unrotated coordinates.
  ///
  /// `/Rotate 90` displays the page turned clockwise, so what the reader calls
  /// the top edge is the `/MediaBox` LEFT edge. Cropping without this takes
  /// the margin off the wrong side of every scanned landscape page - and the
  /// result still looks like a successful crop, just of the wrong edge.
  PageMargins unrotated(int rotate) => switch (rotate) {
    90 => PageMargins(left: top, top: right, right: bottom, bottom: left),
    180 => PageMargins(left: right, top: bottom, right: left, bottom: top),
    270 => PageMargins(left: bottom, top: left, right: top, bottom: right),
    _ => this,
  };

  /// The tightest trim that is safe on both pages: any larger margin would
  /// cut into content on the page that needed the smaller one.
  PageMargins union(PageMargins other) => PageMargins(
    left: left < other.left ? left : other.left,
    bottom: bottom < other.bottom ? bottom : other.bottom,
    right: right < other.right ? right : other.right,
    top: top < other.top ? top : other.top,
  );
}

double mmToPoints(double mm) => mm * 72 / 25.4;
double pointsToMm(double points) => points * 25.4 / 72;

/// [visible] with [margins] trimmed off, or null if nothing would be left.
TextRect? croppedBox(TextRect visible, PageMargins margins) {
  final box = TextRect(
    left: visible.left + margins.left,
    bottom: visible.bottom + margins.bottom,
    right: visible.right - margins.right,
    top: visible.top - margins.top,
  );

  if (box.width < _minimumPageSize || box.height < _minimumPageSize) {
    return null;
  }
  return box;
}

/// The overlap of two boxes, or null when they do not overlap at all.
///
/// `/BleedBox`, `/TrimBox` and `/ArtBox` must lie inside the crop box. Leaving
/// a stale one behind produces a file that is invalid rather than cropped.
TextRect? intersection(TextRect a, TextRect b) {
  final box = TextRect(
    left: a.left > b.left ? a.left : b.left,
    bottom: a.bottom > b.bottom ? a.bottom : b.bottom,
    right: a.right < b.right ? a.right : b.right,
    top: a.top < b.top ? a.top : b.top,
  );
  return box.width <= 0 || box.height <= 0 ? null : box;
}

/// Where the ink stops, as margins in points off each side of [visible].
///
/// Works on the RENDERED page, so the margins it returns are the ones the
/// reader sees - rotation is already applied by the time pixels exist.
///
/// Ink is measured against the page's OWN paper rather than against white. A
/// scan's background is never white: JPEG noise, a grey platen and aged paper
/// all sit around 230-250, and a fixed white threshold calls the entire page
/// ink and finds nothing to trim - on exactly the scanned documents that most
/// need their margins trimmed.
///
/// A page with no ink at all returns nothing to trim. Trimming a blank page to
/// its non-existent content would leave a 3-point square.
PageMargins detectContentMargins(
  Uint8List bgra, {
  required int widthPx,
  required int heightPx,
  required TextRect visible,
  int inkContrast = 24,
  double padding = 6,
}) {
  final luma = Uint8List(widthPx * heightPx);

  for (var i = 0; i < luma.length; i++) {
    final p = i * 4;
    // Rec. 601 luma, as the signature background remover uses. A plain average
    // reads a pale tint - a scan's aged edge - as far darker than the eye
    // does, and every tinted margin then counts as content.
    luma[i] = (bgra[p + 2] * 299 + bgra[p + 1] * 587 + bgra[p] * 114) ~/ 1000;
  }

  // The paper is whatever the page's outer edge mostly is. A margin lies at
  // the edge by definition, so that is where the paper colour is; taking the
  // modal tone of the WHOLE page instead calls a full-bleed image the paper.
  final histogram = List.filled(256, 0);
  for (var x = 0; x < widthPx; x++) {
    histogram[luma[x]]++;
    histogram[luma[(heightPx - 1) * widthPx + x]]++;
  }
  for (var y = 0; y < heightPx; y++) {
    histogram[luma[y * widthPx]]++;
    histogram[luma[y * widthPx + widthPx - 1]]++;
  }

  var paper = 0;
  for (var l = 1; l < 256; l++) {
    if (histogram[l] > histogram[paper]) paper = l;
  }
  final darkest = paper - inkContrast;

  var minX = widthPx;
  var minY = heightPx;
  var maxX = -1;
  var maxY = -1;

  for (var y = 0; y < heightPx; y++) {
    for (var x = 0; x < widthPx; x++) {
      if (luma[y * widthPx + x] >= darkest) continue;

      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX < 0) return const PageMargins();

  final perPointX = widthPx / visible.width;
  final perPointY = heightPx / visible.height;

  double trim(double points) => points - padding < 0 ? 0 : points - padding;

  return PageMargins(
    left: trim(minX / perPointX),
    right: trim((widthPx - 1 - maxX) / perPointX),
    // The raster's first row is the TOP of the page.
    top: trim(minY / perPointY),
    bottom: trim((heightPx - 1 - maxY) / perPointY),
  );
}
