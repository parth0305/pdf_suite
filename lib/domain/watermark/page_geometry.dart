import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// US Letter, used when a document declares no page size anywhere.
const _fallback = TextRect(left: 0, bottom: 0, right: 612, top: 792);

/// How far up the /Parent chain to look before giving up. A damaged document
/// can contain a cycle, and hanging is worse than guessing a page size.
const _maxDepth = 32;

/// The page's `/MediaBox`, resolved through inheritance.
///
/// `/MediaBox` is an inheritable attribute: a page dictionary need not carry
/// one, in which case it comes from an ancestor `/Pages` node. Reading only
/// the page's own dictionary centres a watermark off-page on exactly the
/// documents that rely on inheritance.
///
/// This lives outside `PdfObjectReader` on purpose. Following `/Parent` means
/// reading a node that is not a page dictionary, and that reader's own
/// documentation says a caller needing more than page dictionaries should
/// reconsider scope rather than grow the file.
TextRect mediaBoxOf(PdfObjectIndex index, PdfPageObject page) =>
    _inherited(index, page, _boxIn) ?? _fallback;

/// The page as the reader sees it: `/CropBox` where there is one, clipped to
/// `/MediaBox`, and `/MediaBox` where there is not.
///
/// Cropping an already-cropped page has to start from the visible box. Reading
/// `/MediaBox` instead would silently UNDO an existing crop and call it a crop.
TextRect visibleBoxOf(PdfObjectIndex index, PdfPageObject page) {
  final media = mediaBoxOf(index, page);
  final crop = _inherited(index, page, (d) => _boxIn(d, name: 'CropBox'));
  if (crop == null) return media;

  return TextRect(
    left: crop.left > media.left ? crop.left : media.left,
    bottom: crop.bottom > media.bottom ? crop.bottom : media.bottom,
    right: crop.right < media.right ? crop.right : media.right,
    top: crop.top < media.top ? crop.top : media.top,
  );
}

/// `/Rotate`, normalised to 0, 90, 180 or 270.
///
/// The value is a multiple of 90 that may be negative or exceed a full turn;
/// Dart's `%` on a negative left operand already returns a positive result.
int rotationOf(PdfObjectIndex index, PdfPageObject page) {
  final rotate = _inherited(index, page, (d) {
    final m = RegExp(r'/Rotate\s+(-?\d+)').firstMatch(d);
    return m == null ? null : int.parse(m.group(1)!);
  });
  if (rotate == null) return 0;

  final turns = (rotate ~/ 90) % 4;
  return (turns < 0 ? turns + 4 : turns) * 90;
}

/// Walks `/Parent` until [read] finds the inheritable attribute it wants.
T? _inherited<T>(
  PdfObjectIndex index,
  PdfPageObject page,
  T? Function(String dict) read,
) {
  var dict = page.rawDictionary;

  for (var depth = 0; depth < _maxDepth; depth++) {
    final found = read(dict);
    if (found != null) return found;

    final parent = RegExp(r'/Parent\s+(\d+)\s+\d+\s+R').firstMatch(dict);
    if (parent == null) break;

    final next = index.bodyOf(int.parse(parent.group(1)!));
    if (next == null) break;
    dict = next;
  }

  return null;
}

TextRect? _boxIn(String dict, {String name = 'MediaBox'}) {
  final match = RegExp(
    '/$name'
    r'\s*\[([^\]]*)\]',
  ).firstMatch(dict);
  if (match == null) return null;

  final numbers = RegExp(
    r'-?\d+(?:\.\d+)?',
  ).allMatches(match.group(1)!).map((m) => double.parse(m.group(0)!)).toList();
  if (numbers.length < 4) return null;

  return TextRect(
    left: numbers[0],
    bottom: numbers[1],
    right: numbers[2],
    top: numbers[3],
  );
}
