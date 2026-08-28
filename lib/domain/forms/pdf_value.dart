import 'dart:convert';

/// A PDF value read out of a dictionary, in the three forms a form field's
/// `/V` and `/Opt` actually take.
///
/// Kept apart from the writers' `pdfString`, which only ever has to produce a
/// literal. Reading has to accept every form a producer might have written.
String? readValue(String dict, String key) {
  final at = RegExp(
    '/$key'
    r'(?![A-Za-z0-9])\s*',
  ).firstMatch(dict);
  if (at == null) return null;

  return readValueAt(dict, at.end);
}

/// The value beginning at [start], or null if there is not one there.
String? readValueAt(String dict, int start) {
  if (start >= dict.length) return null;

  switch (dict[start]) {
    case '(':
      return _literal(dict, start + 1);
    case '<':
      // A hex string, not a dictionary: `<<` is the latter.
      if (start + 1 < dict.length && dict[start + 1] == '<') return null;
      final close = dict.indexOf('>', start);
      return close == -1 ? null : _hex(dict.substring(start + 1, close));
    case '/':
      final name = RegExp(
        r'/([^\s/\[\]<>()]*)',
      ).firstMatch(dict.substring(start));
      return name?.group(1);
    default:
      return null;
  }
}

/// The strings in an array, e.g. `/Opt [(Basic) (Pro)]`.
///
/// A choice field may pair an export value with a display one:
/// `[[(BAS) (Basic)] ...]`. The DISPLAYED half is what a person picks from,
/// so it is what is returned; the export value is what gets written back, and
/// [exportValues] returns those in the same order.
List<String> readOptions(String dict) => _options(dict, display: true);

List<String> exportValues(String dict) => _options(dict, display: false);

List<String> _options(String dict, {required bool display}) {
  final at = RegExp(r'/Opt\s*\[').firstMatch(dict);
  if (at == null) return const [];

  final out = <String>[];
  var depth = 1;

  for (var i = at.end; i < dict.length && depth > 0; i++) {
    switch (dict[i]) {
      case '[':
        // A pair. Its first string is the export value, its second the label.
        final pair = <String>[];
        var j = i + 1;
        while (j < dict.length && dict[j] != ']') {
          final value = readValueAt(dict, j);
          if (value != null) {
            pair.add(value);
            j = _endOf(dict, j);
          } else {
            j++;
          }
        }
        if (pair.isNotEmpty) {
          out.add(display && pair.length > 1 ? pair[1] : pair.first);
        }
        i = j;
      case ']':
        depth--;
      case '(':
      case '<':
        final value = readValueAt(dict, i);
        if (value != null) out.add(value);
        i = _endOf(dict, i) - 1;
      default:
        break;
    }
  }

  return out;
}

/// The index just past the value starting at [start].
int _endOf(String dict, int start) {
  if (dict[start] == '(') {
    var depth = 1;
    for (var i = start + 1; i < dict.length; i++) {
      if (dict[i] == r'\') {
        i++;
        continue;
      }
      if (dict[i] == '(') depth++;
      if (dict[i] == ')') {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return dict.length;
  }

  if (dict[start] == '<') {
    final close = dict.indexOf('>', start);
    return close == -1 ? dict.length : close + 1;
  }

  return start + 1;
}

String _literal(String dict, int start) {
  final buffer = StringBuffer();
  var depth = 1;

  for (var i = start; i < dict.length; i++) {
    final ch = dict[i];
    if (ch == r'\') {
      if (i + 1 < dict.length) {
        buffer.write(_escape(dict[i + 1]));
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

  return buffer.toString();
}

String _escape(String ch) => switch (ch) {
  'n' => '\n',
  'r' => '\r',
  't' => '\t',
  _ => ch,
};

/// A hex string. UTF-16BE when it opens with the byte-order mark, which is how
/// anything outside Latin-1 gets into a PDF - a form filled in Hindi, most
/// often.
String _hex(String digits) {
  final clean = digits.replaceAll(RegExp(r'\s'), '');
  final bytes = <int>[];

  for (var i = 0; i + 1 < clean.length; i += 2) {
    final byte = int.tryParse(clean.substring(i, i + 2), radix: 16);
    if (byte == null) return '';
    bytes.add(byte);
  }
  // An odd digit count is padded with a trailing zero, per ISO 32000-1 §7.3.4.
  if (clean.length.isOdd) {
    final byte = int.tryParse('${clean[clean.length - 1]}0', radix: 16);
    if (byte != null) bytes.add(byte);
  }

  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  return latin1.decode(bytes, allowInvalid: true);
}

/// The index just past the value that begins at [start].
///
/// Every form a PDF value can take, because replacing an entry means knowing
/// where the old one ended: a string, a hex string, a name, an array, a
/// dictionary, an indirect reference, or a number. Getting this wrong leaves
/// half an old value in the file, which is a corrupt document rather than a
/// wrong one.
int endOfValueAt(String dict, int start) {
  var i = start;
  while (i < dict.length && _isSpace(dict[i])) {
    i++;
  }
  if (i >= dict.length) return dict.length;

  switch (dict[i]) {
    case '(':
      return _endOfLiteral(dict, i);
    case '[':
      return _endOfBracketed(dict, i, '[', ']');
    case '<':
      if (i + 1 < dict.length && dict[i + 1] == '<') {
        return _endOfBracketed(dict, i, '<<', '>>');
      }
      final close = dict.indexOf('>', i);
      return close == -1 ? dict.length : close + 1;
    case '/':
      final name = RegExp(r'/[^\s/\[\]<>()]*').matchAsPrefix(dict, i);
      return name?.end ?? i + 1;
    default:
      // `12 0 R` is one value, not three. Stopping at the first number leaves
      // `0 R` behind as though it were the next entry.
      final reference = RegExp(r'\d+\s+\d+\s+R').matchAsPrefix(dict, i);
      if (reference != null) return reference.end;

      final token = RegExp(r'[^\s/\[\]<>()]+').matchAsPrefix(dict, i);
      return token?.end ?? i + 1;
  }
}

bool _isSpace(String ch) => ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t';

int _endOfLiteral(String dict, int start) {
  var depth = 0;
  for (var i = start; i < dict.length; i++) {
    if (dict[i] == r'\') {
      i++;
      continue;
    }
    if (dict[i] == '(') depth++;
    if (dict[i] == ')') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return dict.length;
}

int _endOfBracketed(String dict, int start, String open, String close) {
  var depth = 0;
  for (var i = start; i < dict.length; i++) {
    if (dict.startsWith(open, i)) {
      depth++;
      i += open.length - 1;
    } else if (dict.startsWith(close, i)) {
      depth--;
      if (depth == 0) return i + close.length;
      i += close.length - 1;
    } else if (dict[i] == r'\') {
      i++;
    } else if (dict[i] == '(') {
      i = _endOfLiteral(dict, i) - 1;
    }
  }
  return dict.length;
}

/// [dict] with `/key value` set, replacing any entry already there.
///
/// The dictionary keeps its outer `<<` and `>>`.
String withEntry(String dict, String key, String value) {
  final at = RegExp(
    '/$key'
    r'(?![A-Za-z0-9])',
  ).firstMatch(dict);
  if (at == null) {
    final end = dict.lastIndexOf('>>');
    if (end == -1) return dict;
    return '${dict.substring(0, end).trimRight()} /$key $value ${dict.substring(end)}';
  }

  return dict.replaceRange(
    at.start,
    endOfValueAt(dict, at.end),
    '/$key $value',
  );
}

/// [dict] without its `/key` entry, if it has one.
String withoutEntry(String dict, String key) {
  final at = RegExp(
    '/$key'
    r'(?![A-Za-z0-9])',
  ).firstMatch(dict);
  if (at == null) return dict;

  return dict.replaceRange(at.start, endOfValueAt(dict, at.end), '');
}
