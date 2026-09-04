import 'dart:convert';

import 'package:folio/domain/editing/content_stream_parser.dart';

/// A 2-D affine transform, in the order a PDF writes it: `a b c d e f`.
class Matrix {
  const Matrix(this.a, this.b, this.c, this.d, this.e, this.f);

  static const identity = Matrix(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  /// This transform followed by [other].
  ///
  /// Order matters and is the thing everyone gets backwards: text space is
  /// mapped by the text matrix and THEN by the current transformation matrix,
  /// so it is `text * ctm` and never the other way about.
  Matrix then(Matrix other) => Matrix(
    a * other.a + b * other.c,
    a * other.b + b * other.d,
    c * other.a + d * other.c,
    c * other.b + d * other.d,
    e * other.a + f * other.c + other.e,
    e * other.b + f * other.d + other.f,
  );

  /// Where the origin of this transform's space lands.
  ({double x, double y}) get origin => (x: e, y: f);

  /// How much the transform scales vertically, which for text is its size on
  /// the page as opposed to the size it was set in.
  double get verticalScale => (b * b + d * d) <= 0 ? 0 : _sqrt(b * b + d * d);

  static double _sqrt(double value) {
    if (value <= 0) return 0;
    var guess = value;
    for (var i = 0; i < 24; i++) {
      guess = (guess + value / guess) / 2;
    }
    return guess;
  }
}

/// How a show operator wrote its string.
enum TextRunSource {
  /// `(text) Tj`
  show,

  /// `[(a) -120 (b)] TJ` - one run per string in the array.
  showAdjusted,

  /// `(text) '` - next line, then show.
  nextLineShow,

  /// `aw ac (text) "` - word and character spacing, next line, then show.
  spacedNextLineShow,
}

/// One string as it was drawn.
class TextRun {
  const TextRun({
    required this.bytes,
    required this.fontName,
    required this.fontSize,
    required this.transform,
    required this.source,
    required this.operationStart,
    required this.operationEnd,
    required this.stringStart,
    required this.stringEnd,
    required this.renderMode,
  });

  /// The bytes shown, as they were written. What they SAY depends on the
  /// font's encoding, which lives outside a content stream.
  final List<int> bytes;

  /// The resource name of the font, e.g. `F1`, or null when the stream showed
  /// text without setting one - which is malformed, and happens.
  final String? fontName;

  final double fontSize;

  /// Text space to page space, including the font size and the graphics
  /// state. Its origin is where this run starts on the page.
  final Matrix transform;

  final TextRunSource source;

  /// The span of the whole operation, for replacing it outright.
  final int operationStart;
  final int operationEnd;

  /// The span of just this run's string token, for replacing the text and
  /// nothing else - which is what an edit wants when the operator carries
  /// several strings.
  final int stringStart;
  final int stringEnd;

  /// `Tr`. Mode 3 is invisible text, which is what OCR puts under a scan:
  /// editing it changes nothing anybody can see.
  final int renderMode;

  bool get isVisible => renderMode != 3 && renderMode != 7;

  ({double x, double y}) get position => transform.origin;
}

/// Every string drawn by [bytes], with the state it was drawn in.
///
/// A content stream is instructions, not text: where a string lands depends on
/// the text matrix, the line matrix, the graphics state, and the font size at
/// the moment it was shown. Reporting a run without that is reporting that
/// something was drawn somewhere.
///
/// [advanceOf] gives a glyph's width in thousandths, for the font named and
/// the code given. Showing text MOVES the text position, and a document that
/// draws a line in a dozen pieces - which is most of them - puts every piece
/// after the first in the wrong place without it. Absent, the positions after
/// the first show in each text object are the position it started at.
List<TextRun> findTextRuns(
  List<int> bytes, {
  double? Function(String? fontName, int code)? advanceOf,
  int? Function(String? fontName)? codeLengthOf,
}) {
  final out = <TextRun>[];
  final stack = <Matrix>[];

  var ctm = Matrix.identity;
  var textMatrix = Matrix.identity;
  var lineMatrix = Matrix.identity;
  String? fontName;
  var fontSize = 0.0;
  var leading = 0.0;
  var renderMode = 0;
  var horizontalScale = 1.0;
  var rise = 0.0;
  var characterSpacing = 0.0;
  var wordSpacing = 0.0;

  /// How many bytes make one code in the current font. Two for the identity
  /// encodings; the caller says so by what its widths are keyed on.
  var codeLength = 1;

  double number(ContentOperation op, int index) {
    if (index >= op.operands.length) return 0;
    final token = op.operands[index];
    if (token.kind != ContentTokenKind.number) return 0;

    return double.tryParse(
          String.fromCharCodes(bytes.sublist(token.start, token.end)),
        ) ??
        0;
  }

  Matrix renderingMatrix() => Matrix(
    fontSize * horizontalScale,
    0,
    0,
    fontSize,
    0,
    rise,
  ).then(textMatrix).then(ctm);

  void nextLine() {
    lineMatrix = Matrix(1, 0, 0, 1, 0, -leading).then(lineMatrix);
    textMatrix = lineMatrix;
  }

  /// Moves the text position on by what was just drawn.
  ///
  /// ISO 32000-1 9.4.4: each glyph advances by its own width at the text
  /// size, plus the character spacing, plus the word spacing when the code is
  /// a single-byte 32 - all scaled horizontally.
  void advance(List<int> shown, int codeLength) {
    if (advanceOf == null) return;

    var tx = 0.0;

    for (var i = 0; i + codeLength <= shown.length; i += codeLength) {
      var code = 0;
      for (var b = 0; b < codeLength; b++) {
        code = (code << 8) | shown[i + b];
      }

      final width = advanceOf(fontName, code);
      if (width == null) return;

      tx +=
          width / 1000 * fontSize +
          characterSpacing +
          (codeLength == 1 && code == 32 ? wordSpacing : 0);
    }

    textMatrix = Matrix(1, 0, 0, 1, tx * horizontalScale, 0).then(textMatrix);
  }

  /// A kerning number inside a TJ array moves the position too, the other way.
  void adjust(double amount) {
    if (advanceOf == null) return;

    textMatrix = Matrix(
      1,
      0,
      0,
      1,
      -amount / 1000 * fontSize * horizontalScale,
      0,
    ).then(textMatrix);
  }

  void addRun(ContentOperation op, ContentToken token, TextRunSource source) {
    out.add(
      TextRun(
        bytes: _stringBytes(bytes, token),
        fontName: fontName,
        fontSize: fontSize,
        transform: renderingMatrix(),
        source: source,
        operationStart: op.start,
        operationEnd: op.end,
        stringStart: token.start,
        stringEnd: token.end,
        renderMode: renderMode,
      ),
    );
  }

  for (final op in parseContentStream(bytes)) {
    switch (op.operator) {
      case 'q':
        stack.add(ctm);

      case 'Q':
        // An unbalanced Q is a damaged stream, not a reason to stop reading
        // one: the rest of the page still draws.
        if (stack.isNotEmpty) ctm = stack.removeLast();

      case 'cm':
        ctm = Matrix(
          number(op, 0),
          number(op, 1),
          number(op, 2),
          number(op, 3),
          number(op, 4),
          number(op, 5),
        ).then(ctm);

      case 'BT':
        textMatrix = Matrix.identity;
        lineMatrix = Matrix.identity;

      case 'Tf':
        if (op.operands.isNotEmpty &&
            op.operands.first.kind == ContentTokenKind.name) {
          fontName = String.fromCharCodes(
            bytes.sublist(op.operands.first.start + 1, op.operands.first.end),
          );
        }
        fontSize = number(op, 1);
        codeLength = codeLengthOf?.call(fontName) ?? 1;

      case 'Td':
        lineMatrix = Matrix(
          1,
          0,
          0,
          1,
          number(op, 0),
          number(op, 1),
        ).then(lineMatrix);
        textMatrix = lineMatrix;

      case 'TD':
        leading = -number(op, 1);
        lineMatrix = Matrix(
          1,
          0,
          0,
          1,
          number(op, 0),
          number(op, 1),
        ).then(lineMatrix);
        textMatrix = lineMatrix;

      case 'Tm':
        lineMatrix = Matrix(
          number(op, 0),
          number(op, 1),
          number(op, 2),
          number(op, 3),
          number(op, 4),
          number(op, 5),
        );
        textMatrix = lineMatrix;

      case 'T*':
        nextLine();

      case 'TL':
        leading = number(op, 0);

      case 'Tc':
        characterSpacing = number(op, 0);

      case 'Tw':
        wordSpacing = number(op, 0);

      case 'Tz':
        horizontalScale = number(op, 0) / 100;

      case 'Ts':
        rise = number(op, 0);

      case 'Tr':
        renderMode = number(op, 0).round();

      case 'Tj':
        final token = _lastString(op);
        if (token != null) {
          addRun(op, token, TextRunSource.show);
          advance(_stringBytes(bytes, token), codeLength);
        }

      case 'TJ':
        // One run per string: the numbers between them are kerning, and an
        // edit replaces a string without disturbing the shifts around it.
        for (final token in op.operands) {
          if (_isString(token)) {
            addRun(op, token, TextRunSource.showAdjusted);
            advance(_stringBytes(bytes, token), codeLength);
          } else if (token.kind == ContentTokenKind.number) {
            adjust(
              double.tryParse(
                    String.fromCharCodes(bytes.sublist(token.start, token.end)),
                  ) ??
                  0,
            );
          }
        }

      case "'":
        nextLine();
        final token = _lastString(op);
        if (token != null) {
          addRun(op, token, TextRunSource.nextLineShow);
          advance(_stringBytes(bytes, token), codeLength);
        }

      case '"':
        // Its first two operands set the word and character spacing, and they
        // stay set for everything after it.
        wordSpacing = number(op, 0);
        characterSpacing = number(op, 1);
        nextLine();
        final token = _lastString(op);
        if (token != null) {
          addRun(op, token, TextRunSource.spacedNextLineShow);
          advance(_stringBytes(bytes, token), codeLength);
        }
    }
  }

  return out;
}

bool _isString(ContentToken token) =>
    token.kind == ContentTokenKind.literalString ||
    token.kind == ContentTokenKind.hexString;

ContentToken? _lastString(ContentOperation op) {
  for (final token in op.operands.reversed) {
    if (_isString(token)) return token;
  }
  return null;
}

/// The bytes a string token stands for, escapes resolved.
///
/// A literal string's `\n`, `\(` and `\052` are not the bytes that were drawn;
/// they are how those bytes were written down. Measuring or decoding the
/// written form counts the backslashes.
List<int> _stringBytes(List<int> bytes, ContentToken token) {
  if (token.kind == ContentTokenKind.hexString) {
    final digits = <int>[];
    for (var i = token.start + 1; i < token.end - 1; i++) {
      final digit = _hexDigit(bytes[i]);
      if (digit >= 0) digits.add(digit);
    }
    // An odd number of digits is padded with a trailing zero, per
    // ISO 32000-1 7.3.4.3 - so `<4>` is the byte 0x40, not 0x04.
    if (digits.length.isOdd) digits.add(0);

    return [
      for (var i = 0; i < digits.length; i += 2) digits[i] * 16 + digits[i + 1],
    ];
  }

  final out = <int>[];
  var i = token.start + 1;
  final end = token.end - 1;

  while (i < end) {
    if (bytes[i] != 0x5C) {
      out.add(bytes[i]);
      i++;
      continue;
    }

    i++;
    if (i >= end) break;

    final escape = bytes[i];
    switch (escape) {
      case 0x6E:
        out.add(0x0A);
        i++;
      case 0x72:
        out.add(0x0D);
        i++;
      case 0x74:
        out.add(0x09);
        i++;
      case 0x62:
        out.add(0x08);
        i++;
      case 0x66:
        out.add(0x0C);
        i++;
      case 0x0A:
        // A backslash at the end of a line continues the string and adds
        // nothing to it.
        i++;
      case 0x0D:
        i++;
        if (i < end && bytes[i] == 0x0A) i++;
      default:
        if (escape >= 0x30 && escape <= 0x37) {
          var value = 0;
          var digits = 0;
          while (i < end &&
              digits < 3 &&
              bytes[i] >= 0x30 &&
              bytes[i] <= 0x37) {
            value = value * 8 + (bytes[i] - 0x30);
            i++;
            digits++;
          }
          out.add(value & 0xFF);
        } else {
          out.add(escape);
          i++;
        }
    }
  }

  return out;
}

int _hexDigit(int byte) {
  if (byte >= 0x30 && byte <= 0x39) return byte - 0x30;
  if (byte >= 0x41 && byte <= 0x46) return byte - 0x41 + 10;
  if (byte >= 0x61 && byte <= 0x66) return byte - 0x61 + 10;
  return -1;
}

/// The bytes of a run as Latin-1, for tests and for logging.
///
/// NOT a decoding: what a run says depends on the font's encoding, and this
/// is only what the bytes look like read as characters.
String rawTextOf(TextRun run) => latin1.decode(run.bytes, allowInvalid: true);
