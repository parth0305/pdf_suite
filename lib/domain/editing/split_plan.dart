/// How a document is divided into several output documents.
///
/// [groups] holds zero-based page indices; user input is one-based, and the
/// conversion happens here so nothing downstream has to think about it.
class SplitPlan {
  const SplitPlan._(this.groups);

  final List<List<int>> groups;

  int get outputCount => groups.length;

  /// One output document per page.
  factory SplitPlan.everyPage(int pageCount) => SplitPlan._([
    for (var i = 0; i < pageCount; i++) [i],
  ]);

  /// Parses input such as `1-3,7,10-12`.
  ///
  /// Throws [FormatException] with a message suitable for showing to the user.
  factory SplitPlan.parse(String input, {required int pageCount}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter at least one page or range.');
    }

    final groups = <List<int>>[];
    for (final part in trimmed.split(',')) {
      final piece = part.trim();
      if (piece.isEmpty) {
        throw const FormatException('Enter at least one page or range.');
      }

      final bounds = piece.split('-').map((s) => s.trim()).toList();
      if (bounds.length > 2) {
        throw FormatException('"$piece" is not a valid page range.');
      }

      final first = int.tryParse(bounds.first);
      final last = bounds.length == 1 ? first : int.tryParse(bounds[1]);
      if (first == null || last == null) {
        throw FormatException('"$piece" is not a valid page range.');
      }

      if (first < 1 || last < 1) {
        throw const FormatException('Pages are numbered from 1.');
      }
      if (first > pageCount || last > pageCount) {
        throw FormatException(
          'This document has $pageCount pages, so "$piece" is out of range.',
        );
      }
      if (last < first) {
        throw FormatException('"$piece" runs backwards.');
      }

      groups.add([for (var p = first; p <= last; p++) p - 1]);
    }

    return SplitPlan._(groups);
  }
}
