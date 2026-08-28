/// Turning the bytes a run drew into the characters they stand for.
///
/// A content stream says `(48500) Tj`. Which characters those five bytes are
/// depends entirely on the font: a standard encoding, an encoding with
/// exceptions listed, or a mapping carried in the document. A subsetted font
/// may map `A` to byte 3.
///
/// Where the answer cannot be worked out, these say so. Guessing produces a
/// run that reads correctly and re-encodes to something else, which is the
/// failure the whole feature exists to avoid.
library;

/// Reads the bytes of a shown string, and writes text back as the same bytes.
abstract interface class FontDecoder {
  /// The characters [bytes] stand for, or null when they cannot all be
  /// resolved.
  ///
  /// All or nothing on purpose: a partly-read run is worse than an unread one,
  /// because it looks editable and re-encodes wrongly.
  String? decode(List<int> bytes);

  /// [text] as this font's own bytes, or null when it has no way to write
  /// some of it.
  ///
  /// Refusing is the point. A font subsetted for "Invoice 2026" has no `x` in
  /// it; writing one anyway draws nothing, or draws a box, and nothing
  /// reports either.
  List<int>? encode(String text);

  /// The characters of [text] this font cannot write, in the order they
  /// appear. Empty when it can write all of them.
  List<String> missingFrom(String text);
}

/// Reverses a code-to-text table.
///
/// Longest match first, so a ligature mapped from one code is written as that
/// code rather than as its separate letters. Where two codes give the same
/// text the lower one wins, so the same edit always produces the same bytes.
class _Reverse {
  _Reverse(Map<int, String> table) {
    for (final entry in table.entries) {
      if (entry.value.isEmpty) continue;

      final existing = _codes[entry.value];
      if (existing == null || entry.key < existing) {
        _codes[entry.value] = entry.key;
      }
      if (entry.value.length > _longest) _longest = entry.value.length;
    }
  }

  final Map<String, int> _codes = {};
  int _longest = 1;

  /// The codes for [text], or null with the first character it cannot write.
  ({List<int>? codes, List<String> missing}) codesFor(String text) {
    final codes = <int>[];
    final missing = <String>[];
    var at = 0;

    while (at < text.length) {
      var matched = false;

      for (var length = _longest; length >= 1; length--) {
        if (at + length > text.length) continue;

        final code = _codes[text.substring(at, at + length)];
        if (code != null) {
          codes.add(code);
          at += length;
          matched = true;
          break;
        }
      }

      if (!matched) {
        missing.add(text[at]);
        at++;
      }
    }

    return (codes: missing.isEmpty ? codes : null, missing: missing);
  }
}

/// A font whose codes are single bytes, mapped by an encoding table.
class SimpleFontDecoder implements FontDecoder {
  SimpleFontDecoder(this._table) : _reverse = _Reverse(_table);

  /// Byte to character. A missing entry is a byte this font cannot explain.
  final Map<int, String> _table;
  final _Reverse _reverse;

  @override
  String? decode(List<int> bytes) {
    final out = StringBuffer();

    for (final byte in bytes) {
      final character = _table[byte];
      if (character == null) return null;
      out.write(character);
    }

    return out.toString();
  }

  @override
  List<int>? encode(String text) => _reverse.codesFor(text).codes;

  @override
  List<String> missingFrom(String text) => _reverse.codesFor(text).missing;
}

/// A font whose codes are mapped by a `/ToUnicode` CMap carried in the
/// document.
///
/// The most trustworthy case, because the document itself says what its bytes
/// mean - which is exactly why Folio writes one into every font it embeds.
class ToUnicodeDecoder implements FontDecoder {
  ToUnicodeDecoder({required Map<int, String> mapping, required int codeLength})
    : _mapping = mapping,
      _codeLength = codeLength,
      _reverse = _Reverse(mapping);

  final Map<int, String> _mapping;
  final _Reverse _reverse;

  /// How many bytes make one code. Two for the identity encodings, one for
  /// most simple fonts. Reading a two-byte font one byte at a time gives
  /// twice as many characters, all of them wrong.
  final int _codeLength;

  int get codeLength => _codeLength;

  @override
  String? decode(List<int> bytes) {
    if (bytes.length % _codeLength != 0) return null;

    final out = StringBuffer();

    for (var i = 0; i < bytes.length; i += _codeLength) {
      var code = 0;
      for (var b = 0; b < _codeLength; b++) {
        code = (code << 8) | bytes[i + b];
      }

      final character = _mapping[code];
      if (character == null) return null;
      out.write(character);
    }

    return out.toString();
  }

  /// The codes as bytes, most significant first.
  ///
  /// A `/ToUnicode` map is written to be READ, and inverting it is sound only
  /// where it maps each code to a different string. Where it does not, the
  /// lower code wins - so the same edit always writes the same bytes, even if
  /// they are not the ones the original used.
  @override
  List<int>? encode(String text) {
    final codes = _reverse.codesFor(text).codes;
    if (codes == null) return null;

    return [
      for (final code in codes)
        for (var b = _codeLength - 1; b >= 0; b--) (code >> (b * 8)) & 0xFF,
    ];
  }

  @override
  List<String> missingFrom(String text) => _reverse.codesFor(text).missing;
}

/// Reads a `/ToUnicode` CMap.
///
/// Handles the two forms a CMap states mappings in: `bfchar` for one code at a
/// time, and `bfrange` for a run of them - where the destination may itself be
/// a list, one entry per code.
ToUnicodeDecoder? parseToUnicodeCMap(String cmap) {
  final mapping = <int, String>{};
  final codeLength = _codespaceLength(cmap);

  for (final block in _blocks(cmap, 'beginbfchar', 'endbfchar')) {
    for (final match in RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>',
    ).allMatches(block)) {
      final text = _utf16(match.group(2)!);
      if (text != null) mapping[int.parse(match.group(1)!, radix: 16)] = text;
    }
  }

  for (final block in _blocks(cmap, 'beginbfrange', 'endbfrange')) {
    // A destination array gives one value per code, so it has to be read
    // before the plain form, which would otherwise match its first entry and
    // map the whole range to it.
    for (final match in RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[([^\]]*)\]',
    ).allMatches(block)) {
      final from = int.parse(match.group(1)!, radix: 16);
      final destinations = RegExp(
        r'<([0-9A-Fa-f]*)>',
      ).allMatches(match.group(3)!).toList();

      for (var i = 0; i < destinations.length; i++) {
        final text = _utf16(destinations[i].group(1)!);
        if (text != null) mapping[from + i] = text;
      }
    }

    for (final match in RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
    ).allMatches(block)) {
      final from = int.parse(match.group(1)!, radix: 16);
      final to = int.parse(match.group(2)!, radix: 16);
      final base = match.group(3)!;

      // A range longer than the whole of Unicode is a damaged CMap, and
      // filling a map from it would run out of memory rather than fail.
      if (to < from || to - from > 0xFFFF) continue;

      for (var code = from; code <= to; code++) {
        final text = _utf16(base, add: code - from);
        if (text != null) mapping[code] = text;
      }
    }
  }

  return mapping.isEmpty
      ? null
      : ToUnicodeDecoder(mapping: mapping, codeLength: codeLength);
}

/// A decoder for a simple font, from its base encoding and its exceptions.
///
/// `/Differences` is how a document says "in this font, byte 65 is not A". It
/// is applied ON TOP of the base encoding, and ignoring it reads every such
/// font as though the exceptions were not there.
SimpleFontDecoder simpleFontDecoder({
  String? baseEncoding,
  String? differences,
}) {
  final table = <int, String>{
    ...switch (baseEncoding) {
      'WinAnsiEncoding' => _winAnsi,
      'MacRomanEncoding' => _macRoman,
      // StandardEncoding agrees with ASCII across the printable range and
      // differs above it. The bytes it does not explain are reported as
      // unreadable rather than guessed.
      _ => _ascii,
    },
  };

  if (differences != null) {
    var code = 0;

    for (final match in RegExp(
      r'(\d+)|/([^\s/\[\]]+)',
    ).allMatches(differences)) {
      if (match.group(1) != null) {
        code = int.parse(match.group(1)!);
        continue;
      }

      final character = glyphNameToCharacter(match.group(2)!);
      if (character != null) {
        table[code] = character;
      } else {
        table.remove(code);
      }
      code++;
    }
  }

  return SimpleFontDecoder(table);
}

/// The character a glyph name stands for.
///
/// `uni0041` and `u0041` are the forms that state it outright. The rest is a
/// table of the names that turn up in `/Differences`, which is not the whole
/// Adobe glyph list: a name that is not here is reported as unreadable, which
/// is the honest answer.
String? glyphNameToCharacter(String name) {
  final uni = RegExp(r'^uni([0-9A-Fa-f]{4})$').firstMatch(name);
  if (uni != null) {
    return String.fromCharCode(int.parse(uni.group(1)!, radix: 16));
  }

  final u = RegExp(r'^u([0-9A-Fa-f]{4,6})$').firstMatch(name);
  if (u != null) {
    final value = int.parse(u.group(1)!, radix: 16);
    return value <= 0x10FFFF ? String.fromCharCode(value) : null;
  }

  return _glyphNames[name];
}

int _codespaceLength(String cmap) {
  final match = RegExp(
    r'begincodespacerange(.*?)endcodespacerange',
    dotAll: true,
  ).firstMatch(cmap);
  if (match == null) return 1;

  final first = RegExp(r'<([0-9A-Fa-f]+)>').firstMatch(match.group(1)!);
  if (first == null) return 1;

  // Two hex digits to a byte.
  return (first.group(1)!.length / 2).ceil().clamp(1, 4);
}

Iterable<String> _blocks(String cmap, String open, String close) sync* {
  for (final match in RegExp(
    '$open(.*?)$close',
    dotAll: true,
  ).allMatches(cmap)) {
    yield match.group(1)!;
  }
}

/// A hex destination as text, optionally [add] further along.
///
/// The values are UTF-16, so anything above the basic plane arrives as a
/// surrogate pair and has to be put back together.
String? _utf16(String hex, {int add = 0}) {
  if (hex.isEmpty || hex.length.isOdd) return null;

  final units = <int>[];
  for (var i = 0; i + 3 < hex.length + 1; i += 4) {
    if (i + 4 > hex.length) break;
    units.add(int.parse(hex.substring(i, i + 4), radix: 16));
  }
  if (units.isEmpty) return null;

  if (add != 0) units[units.length - 1] += add;

  try {
    return String.fromCharCodes(units);
  } on ArgumentError {
    return null;
  }
}

Map<int, String> get _ascii => {
  for (var code = 32; code < 127; code++) code: String.fromCharCode(code),
};

/// WinAnsi agrees with Latin-1 except between 0x80 and 0x9F, where Latin-1 has
/// control characters and WinAnsi has punctuation. Reading one as the other
/// turns every curly quote into a control character.
Map<int, String> get _winAnsi => {
  ..._ascii,
  for (var code = 0xA0; code <= 0xFF; code++) code: String.fromCharCode(code),
  0x80: '€',
  0x82: '‚',
  0x83: 'ƒ',
  0x84: '„',
  0x85: '…',
  0x86: '†',
  0x87: '‡',
  0x88: 'ˆ',
  0x89: '‰',
  0x8A: 'Š',
  0x8B: '‹',
  0x8C: 'Œ',
  0x8E: 'Ž',
  0x91: '‘',
  0x92: '’',
  0x93: '“',
  0x94: '”',
  0x95: '•',
  0x96: '–',
  0x97: '—',
  0x98: '˜',
  0x99: '™',
  0x9A: 'š',
  0x9B: '›',
  0x9C: 'œ',
  0x9E: 'ž',
  0x9F: 'Ÿ',
};

/// MacRoman shares nothing with Latin-1 above 0x7F.
Map<int, String> get _macRoman => {
  ..._ascii,
  0x80: 'Ä',
  0x81: 'Å',
  0x82: 'Ç',
  0x83: 'É',
  0x84: 'Ñ',
  0x85: 'Ö',
  0x86: 'Ü',
  0x87: 'á',
  0x88: 'à',
  0x89: 'â',
  0x8A: 'ä',
  0x8B: 'ã',
  0x8C: 'å',
  0x8D: 'ç',
  0x8E: 'é',
  0x8F: 'è',
  0x90: 'ê',
  0x91: 'ë',
  0x92: 'í',
  0x93: 'ì',
  0x94: 'î',
  0x95: 'ï',
  0x96: 'ñ',
  0x97: 'ó',
  0x98: 'ò',
  0x99: 'ô',
  0x9A: 'ö',
  0x9B: 'õ',
  0x9C: 'ú',
  0x9D: 'ù',
  0x9E: 'û',
  0x9F: 'ü',
  0xA0: '†',
  0xA1: '°',
  0xA2: '¢',
  0xA3: '£',
  0xA4: '§',
  0xA5: '•',
  0xA6: '¶',
  0xA7: 'ß',
  0xA8: '®',
  0xA9: '©',
  0xAA: '™',
  0xAB: '´',
  0xAC: '¨',
  0xAD: '≠',
  0xAE: 'Æ',
  0xAF: 'Ø',
  0xB0: '∞',
  0xB1: '±',
  0xB2: '≤',
  0xB3: '≥',
  0xB4: '¥',
  0xB5: 'µ',
  0xB6: '∂',
  0xB7: '∑',
  0xB8: '∏',
  0xB9: 'π',
  0xBA: '∫',
  0xBB: 'ª',
  0xBC: 'º',
  0xBD: 'Ω',
  0xBE: 'æ',
  0xBF: 'ø',
  0xC0: '¿',
  0xC1: '¡',
  0xC2: '¬',
  0xC3: '√',
  0xC4: 'ƒ',
  0xC5: '≈',
  0xC6: '∆',
  0xC7: '«',
  0xC8: '»',
  0xC9: '…',
  0xCA: ' ',
  0xCB: 'À',
  0xCC: 'Ã',
  0xCD: 'Õ',
  0xCE: 'Œ',
  0xCF: 'œ',
  0xD0: '–',
  0xD1: '—',
  0xD2: '“',
  0xD3: '”',
  0xD4: '‘',
  0xD5: '’',
  0xD6: '÷',
  0xD7: '◊',
  0xD8: 'ÿ',
  0xD9: 'Ÿ',
  0xDA: '⁄',
  0xDB: '€',
  0xDC: '‹',
  0xDD: '›',
  0xDE: 'ﬁ',
  0xDF: 'ﬂ',
  0xE0: '‡',
  0xE1: '·',
  0xE2: '‚',
  0xE3: '„',
  0xE4: '‰',
  0xE5: 'Â',
  0xE6: 'Ê',
  0xE7: 'Á',
  0xE8: 'Ë',
  0xE9: 'È',
  0xEA: 'Í',
  0xEB: 'Î',
  0xEC: 'Ï',
  0xED: 'Ì',
  0xEE: 'Ó',
  0xEF: 'Ô',
  0xF1: 'Ò',
  0xF2: 'Ú',
  0xF3: 'Û',
  0xF4: 'Ù',
  0xF5: 'ı',
  0xF6: 'ˆ',
  0xF7: '˜',
  0xF8: '¯',
  0xF9: '˘',
  0xFA: '˙',
  0xFB: '˚',
  0xFC: '¸',
  0xFD: '˝',
  0xFE: '˛',
  0xFF: 'ˇ',
};

/// The glyph names that turn up in a `/Differences` array. Not the whole
/// Adobe glyph list: a name missing from here is reported unreadable, which
/// is better than a wrong character.
const _glyphNames = <String, String>{
  'space': ' ',
  'exclam': '!',
  'quotedbl': '"',
  'numbersign': '#',
  'dollar': r'$',
  'percent': '%',
  'ampersand': '&',
  'quotesingle': "'",
  'parenleft': '(',
  'parenright': ')',
  'asterisk': '*',
  'plus': '+',
  'comma': ',',
  'hyphen': '-',
  'period': '.',
  'slash': '/',
  'zero': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
  'colon': ':',
  'semicolon': ';',
  'less': '<',
  'equal': '=',
  'greater': '>',
  'question': '?',
  'at': '@',
  'bracketleft': '[',
  'backslash': r'\',
  'bracketright': ']',
  'asciicircum': '^',
  'underscore': '_',
  'grave': '`',
  'braceleft': '{',
  'bar': '|',
  'braceright': '}',
  'asciitilde': '~',
  'quoteleft': '‘',
  'quoteright': '’',
  'quotedblleft': '“',
  'quotedblright': '”',
  'endash': '–',
  'emdash': '—',
  'bullet': '•',
  'ellipsis': '…',
  'dagger': '†',
  'daggerdbl': '‡',
  'perthousand': '‰',
  'guilsinglleft': '‹',
  'guilsinglright': '›',
  'fraction': '⁄',
  'florin': 'ƒ',
  'trademark': '™',
  'Euro': '€',
  'sterling': '£',
  'yen': '¥',
  'cent': '¢',
  'currency': '¤',
  'section': '§',
  'paragraph': '¶',
  'copyright': '©',
  'registered': '®',
  'degree': '°',
  'plusminus': '±',
  'multiply': '×',
  'divide': '÷',
  'onehalf': '½',
  'onequarter': '¼',
  'threequarters': '¾',
  'periodcentered': '·',
  'brokenbar': '¦',
  'exclamdown': '¡',
  'questiondown': '¿',
  'guillemotleft': '«',
  'guillemotright': '»',
  'ordfeminine': 'ª',
  'ordmasculine': 'º',
  'logicalnot': '¬',
  'macron': '¯',
  'acute': '´',
  'cedilla': '¸',
  'dieresis': '¨',
  'germandbls': 'ß',
  'AE': 'Æ',
  'ae': 'æ',
  'OE': 'Œ',
  'oe': 'œ',
  'Oslash': 'Ø',
  'oslash': 'ø',
  'Aacute': 'Á',
  'aacute': 'á',
  'Agrave': 'À',
  'agrave': 'à',
  'Acircumflex': 'Â',
  'acircumflex': 'â',
  'Adieresis': 'Ä',
  'adieresis': 'ä',
  'Atilde': 'Ã',
  'atilde': 'ã',
  'Aring': 'Å',
  'aring': 'å',
  'Ccedilla': 'Ç',
  'ccedilla': 'ç',
  'Eacute': 'É',
  'eacute': 'é',
  'Egrave': 'È',
  'egrave': 'è',
  'Ecircumflex': 'Ê',
  'ecircumflex': 'ê',
  'Edieresis': 'Ë',
  'edieresis': 'ë',
  'Iacute': 'Í',
  'iacute': 'í',
  'Igrave': 'Ì',
  'igrave': 'ì',
  'Ntilde': 'Ñ',
  'ntilde': 'ñ',
  'Oacute': 'Ó',
  'oacute': 'ó',
  'Ograve': 'Ò',
  'ograve': 'ò',
  'Odieresis': 'Ö',
  'odieresis': 'ö',
  'Uacute': 'Ú',
  'uacute': 'ú',
  'Ugrave': 'Ù',
  'ugrave': 'ù',
  'Udieresis': 'Ü',
  'udieresis': 'ü',
  'Yacute': 'Ý',
  'yacute': 'ý',
  'ydieresis': 'ÿ',
  'fi': 'ﬁ',
  'fl': 'ﬂ',
};
