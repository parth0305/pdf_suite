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
TextRect mediaBoxOf(PdfObjectIndex index, PdfPageObject page) {
  var dict = page.rawDictionary;

  for (var depth = 0; depth < _maxDepth; depth++) {
    final box = _boxIn(dict);
    if (box != null) return box;

    final parent = RegExp(r'/Parent\s+(\d+)\s+\d+\s+R').firstMatch(dict);
    if (parent == null) break;

    final next = index.bodyOf(int.parse(parent.group(1)!));
    if (next == null) break;
    dict = next;
  }

  return _fallback;
}

TextRect? _boxIn(String dict) {
  final match = RegExp(r'/MediaBox\s*\[([^\]]*)\]').firstMatch(dict);
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
