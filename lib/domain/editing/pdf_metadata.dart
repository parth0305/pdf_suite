import 'dart:convert';
import 'dart:typed_data';

/// A PDF document information dictionary.
///
/// Read from and written to a PDF's `/Info` entry. Deliberately byte-level and
/// dependency-free: it works on the output of any writer without needing an
/// object model, and unit-tests with no simulator.
///
/// Folio never adds `/Producer` or `/ModDate`. A document you edit should not
/// start advertising which tool touched it or when.
class PdfMetadata {
  const PdfMetadata({
    this.title,
    this.author,
    this.subject,
    this.keywords,
    this.creator,
  });

  final String? title;
  final String? author;
  final String? subject;
  final String? keywords;
  final String? creator;

  bool get isEmpty =>
      title == null &&
      author == null &&
      subject == null &&
      keywords == null &&
      creator == null;

  static const Map<String, String> _keys = {
    'Title': 'title',
    'Author': 'author',
    'Subject': 'subject',
    'Keywords': 'keywords',
    'Creator': 'creator',
  };

  /// Reads `/Info` by walking to the last trailer and resolving its reference.
  ///
  /// Returns null when the document has no `/Info`, or when the bytes cannot be
  /// understood - callers get an absence, never an exception.
  static PdfMetadata? readFrom(Uint8List pdf) {
    try {
      final text = latin1.decode(pdf, allowInvalid: true);

      // The last trailer wins: an incremental update appends a newer one.
      final trailerAt = text.lastIndexOf('trailer');
      if (trailerAt < 0) return null;

      final ref = RegExp(
        r'/Info\s+(\d+)\s+(\d+)\s+R',
      ).firstMatch(text.substring(trailerAt));
      if (ref == null) return null;

      final objNum = ref.group(1)!;
      // The last definition wins, for the same reason the last trailer does.
      final defs = RegExp(
        '(?:^|[^0-9])$objNum\\s+0\\s+obj(.*?)endobj',
        dotAll: true,
      ).allMatches(text).toList();
      if (defs.isEmpty) return null;

      final body = defs.last.group(1)!;
      final values = <String, String>{};
      for (final key in _keys.keys) {
        final value = _readEntry(body, key);
        if (value != null) values[key] = value;
      }

      return PdfMetadata(
        title: values['Title'],
        author: values['Author'],
        subject: values['Subject'],
        keywords: values['Keywords'],
        creator: values['Creator'],
      );
    } catch (_) {
      return null;
    }
  }

  /// Extracts one `/Key (value)` entry, honouring backslash escapes and nested
  /// parentheses, which a plain regex cannot do correctly.
  static String? _readEntry(String body, String key) {
    final start = RegExp('/$key\\s*\\(').firstMatch(body);
    if (start == null) return null;

    final buffer = StringBuffer();
    var depth = 1;
    for (var i = start.end; i < body.length; i++) {
      final ch = body[i];
      if (ch == r'\') {
        if (i + 1 < body.length) {
          buffer.write(body[i + 1]);
          i++;
        }
        continue;
      }
      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) return buffer.toString();
      }
      buffer.write(ch);
    }
    return null;
  }

  /// Appends an incremental update attaching this metadata.
  ///
  /// The original bytes are left untouched; new objects, a new xref section and
  /// a trailer whose `/Prev` chains to the previous one are added at the end.
  /// Readers walk that chain backwards, so the new `/Info` supersedes any older
  /// one without rewriting the document.
  ///
  /// Assumes a classic xref table, which is what our own writer emits. It would
  /// need extending for PDF 1.5+ cross-reference streams.
  Uint8List appendTo(Uint8List pdf) {
    if (isEmpty) return pdf;

    final text = latin1.decode(pdf, allowInvalid: true);

    final startxref = RegExp(
      r'startxref\s+(\d+)\s*%%EOF\s*$',
    ).firstMatch(text.trimRight());
    if (startxref == null) {
      throw const FormatException('no startxref: not a classic-xref PDF');
    }

    final roots = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R').allMatches(text);
    final sizes = RegExp(r'/Size\s+(\d+)').allMatches(text);
    if (roots.isEmpty || sizes.isEmpty) {
      throw const FormatException('trailer has no /Root or /Size');
    }

    final root = roots.last;
    final prevOffset = int.parse(startxref.group(1)!);
    final objNum = int.parse(sizes.last.group(1)!);

    final entries = <String>[
      if (title != null) '/Title ${_literal(title!)}',
      if (author != null) '/Author ${_literal(author!)}',
      if (subject != null) '/Subject ${_literal(subject!)}',
      if (keywords != null) '/Keywords ${_literal(keywords!)}',
      if (creator != null) '/Creator ${_literal(creator!)}',
    ];

    final out = <int>[...pdf];
    if (out.isNotEmpty && out.last != 0x0a) out.add(0x0a);

    final infoOffset = out.length;
    out.addAll(
      latin1.encode('$objNum 0 obj\n<< ${entries.join(' ')} >>\nendobj\n'),
    );

    final xrefOffset = out.length;
    out.addAll(
      latin1.encode(
        'xref\n'
        '$objNum 1\n'
        '${infoOffset.toString().padLeft(10, '0')} 00000 n \n'
        'trailer\n'
        '<< /Size ${objNum + 1} '
        '/Root ${root.group(1)} ${root.group(2)} R '
        '/Info $objNum 0 R '
        '/Prev $prevOffset >>\n'
        'startxref\n$xrefOffset\n%%EOF\n',
      ),
    );

    return Uint8List.fromList(out);
  }

  /// Renders a PDF string literal.
  ///
  /// Backslash first, or it would escape the escapes added afterwards. An
  /// unescaped delimiter here corrupts the whole document.
  static String _literal(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    return '($escaped)';
  }
}
