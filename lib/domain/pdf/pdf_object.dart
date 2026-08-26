import 'dart:convert';

/// One indirect object, captured as raw bytes.
class PdfObject {
  const PdfObject({
    required this.number,
    required this.generation,
    required this.body,
  });

  final int number;
  final int generation;

  /// Everything between `obj` and `endobj`, streams included.
  final List<int> body;
}

/// Every indirect object in [bytes], in file order.
///
/// A stream's declared `/Length` is honoured when looking for the end of an
/// object: binary stream data can contain the bytes `endobj`, and searching
/// for that word would end the object inside its own stream and corrupt
/// everything after it.
List<PdfObject> parsePdfObjects(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final objects = <PdfObject>[];

  for (final match in RegExp(r'(\d+)\s+(\d+)\s+obj').allMatches(text)) {
    final start = match.end;

    final endAt = text.indexOf('endobj', start);
    final streamAt = text.indexOf('stream', start);
    var searchFrom = start;

    // Only treat it as a stream if `stream` comes before this object's end.
    if (streamAt >= 0 && (endAt < 0 || streamAt < endAt)) {
      final length = RegExp(
        r'/Length\s+(\d+)',
      ).firstMatch(text.substring(start, streamAt));
      if (length != null) {
        var dataStart = streamAt + 'stream'.length;
        // The keyword is followed by CRLF or LF, never CR alone.
        if (text.startsWith('\r\n', dataStart)) {
          dataStart += 2;
        } else if (text.startsWith('\n', dataStart)) {
          dataStart += 1;
        }
        searchFrom = dataStart + int.parse(length.group(1)!);
      }
    }

    final end = text.indexOf('endobj', searchFrom);
    // A truncated object is a damaged document, not a reason to throw.
    if (end < 0) continue;

    objects.add(
      PdfObject(
        number: int.parse(match.group(1)!),
        generation: int.parse(match.group(2)!),
        body: bytes.sublist(start, end),
      ),
    );
  }

  return objects;
}
