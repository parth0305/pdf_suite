/// Reads a page's drawing instructions.
///
/// Redaction and watermarking both deliberately avoided this: they append to a
/// content stream or replace it wholesale, and neither needs to know what is
/// in one. Editing text does.
library;

/// What a token is.
enum ContentTokenKind {
  number,
  name,
  literalString,
  hexString,
  arrayStart,
  arrayEnd,
  dictionaryStart,
  dictionaryEnd,
  operator,

  /// `BI ... ID <bytes> EI`. Held whole, because its payload is not
  /// instructions and must never be read as any.
  inlineImage,

  comment,
}

/// One token, as a span of the ORIGINAL bytes.
///
/// A span rather than a value, so re-emitting is copying and an edit changes
/// only what it touches. The same principle the incremental writers use: leave
/// everything else byte for byte alone.
class ContentToken {
  const ContentToken({
    required this.kind,
    required this.start,
    required this.end,
  });

  final ContentTokenKind kind;
  final int start;
  final int end;
}

/// An operator and the operands it was given.
class ContentOperation {
  const ContentOperation({
    required this.operator,
    required this.operands,
    required this.start,
    required this.end,
  });

  /// The operator itself, e.g. `Tj`, `TJ`, `Tf`, `re`.
  final String operator;

  /// Its operands, in the order they appeared.
  final List<ContentToken> operands;

  /// The span covering the operands AND the operator, so replacing an
  /// operation means replacing this range.
  final int start;
  final int end;
}

/// Every token in [bytes], in order.
///
/// Guaranteed to terminate on any input, including a damaged one: every token
/// consumes at least one byte, which [tokensAdvance] states as a property and
/// the tests assert. A parser fed arbitrary files that can loop forever does
/// not fail, it freezes - and this one is fed whatever a user opens.
List<ContentToken> tokenizeContentStream(List<int> bytes) {
  final out = <ContentToken>[];
  var at = 0;

  while (at < bytes.length) {
    at = _skipWhitespace(bytes, at);
    if (at >= bytes.length) break;

    final start = at;
    final byte = bytes[at];

    if (byte == 0x25) {
      // A comment runs to the end of the line.
      while (at < bytes.length && bytes[at] != 0x0A && bytes[at] != 0x0D) {
        at++;
      }
      out.add(
        ContentToken(kind: ContentTokenKind.comment, start: start, end: at),
      );
      continue;
    }

    if (byte == 0x28) {
      at = _endOfLiteralString(bytes, at);
      out.add(
        ContentToken(
          kind: ContentTokenKind.literalString,
          start: start,
          end: at,
        ),
      );
      continue;
    }

    if (byte == 0x3C) {
      if (at + 1 < bytes.length && bytes[at + 1] == 0x3C) {
        out.add(
          ContentToken(
            kind: ContentTokenKind.dictionaryStart,
            start: start,
            end: at + 2,
          ),
        );
        at += 2;
        continue;
      }
      while (at < bytes.length && bytes[at] != 0x3E) {
        at++;
      }
      final closed = at < bytes.length;
      out.add(
        ContentToken(
          kind: ContentTokenKind.hexString,
          start: start,
          end: closed ? at + 1 : at,
        ),
      );
      at = closed ? at + 1 : at;
      continue;
    }

    if (byte == 0x3E && at + 1 < bytes.length && bytes[at + 1] == 0x3E) {
      out.add(
        ContentToken(
          kind: ContentTokenKind.dictionaryEnd,
          start: start,
          end: at + 2,
        ),
      );
      at += 2;
      continue;
    }

    if (byte == 0x5B || byte == 0x5D) {
      out.add(
        ContentToken(
          kind: byte == 0x5B
              ? ContentTokenKind.arrayStart
              : ContentTokenKind.arrayEnd,
          start: start,
          end: at + 1,
        ),
      );
      at++;
      continue;
    }

    if (byte == 0x2F) {
      at++;
      while (at < bytes.length &&
          !_isDelimiter(bytes[at]) &&
          !_isWhitespace(bytes[at])) {
        at++;
      }
      out.add(ContentToken(kind: ContentTokenKind.name, start: start, end: at));
      continue;
    }

    if (_startsNumber(bytes, at)) {
      at++;
      while (at < bytes.length &&
          (_isDigit(bytes[at]) ||
              bytes[at] == 0x2E ||
              bytes[at] == 0x2D ||
              bytes[at] == 0x2B)) {
        at++;
      }
      out.add(
        ContentToken(kind: ContentTokenKind.number, start: start, end: at),
      );
      continue;
    }

    // Anything else is an operator: a run of characters up to a delimiter.
    while (at < bytes.length &&
        !_isDelimiter(bytes[at]) &&
        !_isWhitespace(bytes[at])) {
      at++;
    }
    // A lone delimiter that reached here is not an operator; step past it so
    // a damaged stream cannot loop forever.
    if (at == start) at++;

    final word = String.fromCharCodes(bytes.sublist(start, at));

    if (word == 'BI') {
      final end = _endOfInlineImage(bytes, at);
      out.add(
        ContentToken(
          kind: ContentTokenKind.inlineImage,
          start: start,
          end: end,
        ),
      );
      at = end;
      continue;
    }

    out.add(
      ContentToken(kind: ContentTokenKind.operator, start: start, end: at),
    );
  }

  return out;
}

/// Whether [tokens] cover [bytes] in order, each one consuming at least one
/// byte and none overlapping the next.
///
/// The property that makes tokenising terminate. Exposed because it is worth
/// asserting on real streams, not only reasoning about.
bool tokensAdvance(List<int> bytes, List<ContentToken> tokens) {
  var previous = 0;

  for (final token in tokens) {
    if (token.end <= token.start) return false;
    if (token.start < previous) return false;
    if (token.end > bytes.length) return false;
    previous = token.end;
  }

  return true;
}

/// The stream's operations: operands gathered up to each operator.
///
/// Tokens that are not part of an operation - comments, and operands left
/// dangling by a damaged stream - are not returned. Re-emitting works from the
/// TOKENS, not from these, so nothing is lost by leaving them out.
List<ContentOperation> parseContentStream(List<int> bytes) {
  final tokens = tokenizeContentStream(bytes);
  final out = <ContentOperation>[];
  var operands = <ContentToken>[];

  for (final token in tokens) {
    switch (token.kind) {
      case ContentTokenKind.comment:
        continue;

      case ContentTokenKind.inlineImage:
        out.add(
          ContentOperation(
            operator: 'BI',
            operands: const [],
            start: token.start,
            end: token.end,
          ),
        );
        operands = <ContentToken>[];

      case ContentTokenKind.operator:
        out.add(
          ContentOperation(
            operator: String.fromCharCodes(
              bytes.sublist(token.start, token.end),
            ),
            operands: List.of(operands),
            start: operands.isEmpty ? token.start : operands.first.start,
            end: token.end,
          ),
        );
        operands = <ContentToken>[];

      default:
        operands.add(token);
    }
  }

  return out;
}

/// The end of a literal string beginning at [at].
///
/// Brackets nest, and a backslash escapes the next byte - including a bracket,
/// and including another backslash. Counting brackets without honouring
/// escapes ends the string in the middle of `\)` and turns the rest of the
/// page into operators.
int _endOfLiteralString(List<int> bytes, int at) {
  var depth = 0;
  var i = at;

  while (i < bytes.length) {
    final byte = bytes[i];

    if (byte == 0x5C) {
      i += 2;
      continue;
    }
    if (byte == 0x28) depth++;
    if (byte == 0x29) {
      depth--;
      if (depth == 0) return i + 1;
    }
    i++;
  }

  return bytes.length;
}

/// The end of an inline image beginning at [at], which is just past `BI`.
///
/// The payload after `ID` is image data, not instructions: it can contain the
/// bytes `EI`, every operator name, and unbalanced brackets. The end is the
/// first `EI` that is preceded by whitespace and followed by a delimiter or
/// whitespace - which is what every reader uses, and is still a heuristic,
/// because the format provides nothing better.
int _endOfInlineImage(List<int> bytes, int at) {
  var i = at;

  // Find ID, which ends the dictionary and begins the data.
  while (i + 1 < bytes.length) {
    if (bytes[i] == 0x49 && bytes[i + 1] == 0x44) {
      i += 2;
      break;
    }
    i++;
  }
  // The single whitespace byte after ID separates it from the data. Skipping
  // it would matter to a reader that decoded the image; this one holds the
  // whole thing as a span, so where the data starts changes nothing, and a
  // line that changes nothing is a line that looks like it does.

  while (i + 1 < bytes.length) {
    if (bytes[i] == 0x45 &&
        bytes[i + 1] == 0x49 &&
        i > at &&
        _isWhitespace(bytes[i - 1]) &&
        (i + 2 >= bytes.length ||
            _isWhitespace(bytes[i + 2]) ||
            _isDelimiter(bytes[i + 2]))) {
      return i + 2;
    }
    i++;
  }

  return bytes.length;
}

bool _startsNumber(List<int> bytes, int at) {
  final byte = bytes[at];
  if (_isDigit(byte) || byte == 0x2E) return true;

  // A sign only starts a number when a digit or point follows it; `-` alone is
  // not an operand.
  if (byte != 0x2B && byte != 0x2D) return false;
  if (at + 1 >= bytes.length) return false;

  return _isDigit(bytes[at + 1]) || bytes[at + 1] == 0x2E;
}

bool _isDigit(int byte) => byte >= 0x30 && byte <= 0x39;

bool _isWhitespace(int byte) =>
    byte == 0x00 ||
    byte == 0x09 ||
    byte == 0x0A ||
    byte == 0x0C ||
    byte == 0x0D ||
    byte == 0x20;

bool _isDelimiter(int byte) =>
    byte == 0x28 ||
    byte == 0x29 ||
    byte == 0x3C ||
    byte == 0x3E ||
    byte == 0x5B ||
    byte == 0x5D ||
    byte == 0x7B ||
    byte == 0x7D ||
    byte == 0x2F ||
    byte == 0x25;

int _skipWhitespace(List<int> bytes, int at) {
  var i = at;
  while (i < bytes.length && _isWhitespace(bytes[i])) {
    i++;
  }
  return i;
}
