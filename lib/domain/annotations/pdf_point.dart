/// A point in PDF user space, where y grows **upward** from the bottom-left of
/// the page.
///
/// New in SP-3b: text markup only ever needed rectangles, so no point type
/// existed before drawing.
class PdfPoint {
  const PdfPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is PdfPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PdfPoint($x, $y)';
}
