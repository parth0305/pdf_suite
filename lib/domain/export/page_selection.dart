/// Parses a page range like `1-3, 7, 9-` into zero-based indices.
///
/// One-based on the way in, because that is what the page indicator shows and
/// what anyone typing a range means. Zero-based on the way out, because that is
/// what every reader takes.
///
/// An empty or unparseable range yields every page rather than none: exporting
/// nothing because of a typo is a worse failure than exporting too much.
List<int> parsePageRange(String range, {required int pageCount}) {
  final trimmed = range.trim();
  if (trimmed.isEmpty) return [for (var i = 0; i < pageCount; i++) i];

  final chosen = <int>{};

  for (final part in trimmed.split(',')) {
    final piece = part.trim();
    if (piece.isEmpty) continue;

    final dash = piece.indexOf('-');
    if (dash < 0) {
      final one = int.tryParse(piece);
      if (one != null) chosen.add(one - 1);
      continue;
    }

    // An open end - "9-" - means "to the last page", which is what someone
    // writing it means and what leaving it off would otherwise refuse.
    final from = int.tryParse(piece.substring(0, dash).trim()) ?? 1;
    final toText = piece.substring(dash + 1).trim();
    final to = toText.isEmpty ? pageCount : int.tryParse(toText) ?? pageCount;

    for (var p = from; p <= to; p++) {
      chosen.add(p - 1);
    }
  }

  final valid = chosen.where((i) => i >= 0 && i < pageCount).toList()..sort();

  return valid.isEmpty ? [for (var i = 0; i < pageCount; i++) i] : valid;
}

/// Converts PDFium's BGRA output to the RGBA an encoder wants.
List<int> bgraToRgba(List<int> bgra) {
  final rgba = List<int>.filled(bgra.length, 0);

  for (var p = 0; p < bgra.length; p += 4) {
    rgba[p] = bgra[p + 2];
    rgba[p + 1] = bgra[p + 1];
    rgba[p + 2] = bgra[p];
    rgba[p + 3] = bgra[p + 3];
  }

  return rgba;
}

/// A filename for one exported page.
///
/// Zero-padded so a folder of them sorts the way the document reads: page 10
/// after page 9, not between 1 and 2.
String pageImageName(String documentName, int pageNumber, int pageCount) {
  final stem = documentName.replaceAll(
    RegExp(r'\.pdf$', caseSensitive: false),
    '',
  );
  final width = pageCount.toString().length;

  return '$stem page ${pageNumber.toString().padLeft(width, '0')}.png';
}
