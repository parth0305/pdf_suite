/// One page in an edit session: which source document it came from, which page
/// within that document, and how far it has been rotated.
///
/// A slot never holds PDF bytes. Editing is staged as a list of these, and only
/// materialised when the user applies the changes.
class PageSlot {
  const PageSlot({
    required this.sourceDocumentId,
    required this.sourcePageIndex,
    this.quarterTurns = 0,
  });

  final int sourceDocumentId;
  final int sourcePageIndex;

  /// Always normalised to 0..3.
  final int quarterTurns;

  bool get isRotated => quarterTurns != 0;

  /// Returns a slot rotated by [quarterTurns] more, wrapping through 0..3 so
  /// four turns is identity and negative turns wrap rather than go negative.
  PageSlot rotatedBy(int quarterTurns) => PageSlot(
    sourceDocumentId: sourceDocumentId,
    sourcePageIndex: sourcePageIndex,
    // Dart's % returns a non-negative result for a positive divisor, which is
    // what makes rotatedBy(-1) land on 3 rather than -1.
    quarterTurns: (this.quarterTurns + quarterTurns) % 4,
  );

  @override
  bool operator ==(Object other) =>
      other is PageSlot &&
      other.sourceDocumentId == sourceDocumentId &&
      other.sourcePageIndex == sourcePageIndex &&
      other.quarterTurns == quarterTurns;

  @override
  int get hashCode =>
      Object.hash(sourceDocumentId, sourcePageIndex, quarterTurns);

  @override
  String toString() =>
      'PageSlot(doc: $sourceDocumentId, page: $sourcePageIndex, '
      'turns: $quarterTurns)';
}
