import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/content_stream_parser.dart';

import '../../../scripts/pdf_fixture_builder.dart';

List<int> of(String source) => latin1.encode(source);

String textOf(List<int> bytes, ContentToken token) =>
    latin1.decode(bytes.sublist(token.start, token.end));

/// The tokens put back together, with the bytes between them.
///
/// The parser's whole contract: a token is a SPAN, so re-emitting is copying,
/// and an edit changes only what it touches. If this does not reproduce the
/// input exactly then something has been quietly rewritten.
List<int> reemit(List<int> bytes, List<ContentToken> tokens) {
  final out = <int>[];
  var at = 0;

  for (final token in tokens) {
    out
      ..addAll(bytes.sublist(at, token.start))
      ..addAll(bytes.sublist(token.start, token.end));
    at = token.end;
  }

  return out..addAll(bytes.sublist(at));
}

/// Every content stream in a PDF, inflated where it is compressed.
List<List<int>> streamsIn(List<int> pdf) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final out = <List<int>>[];

  for (final match in RegExp(
    r'<<([^>]*)>>\s*stream\r?\n',
    dotAll: true,
  ).allMatches(text)) {
    final start = match.end;
    final end = text.indexOf('endstream', start);
    if (end == -1) continue;

    final raw = pdf.sublist(start, end);
    out.add(
      match.group(1)!.contains('FlateDecode') ? ZLibCodec().decode(raw) : raw,
    );
  }

  return out;
}

void main() {
  group('round trip', () {
    for (final entry in {
      'a text object': 'BT /F1 12 Tf 72 700 Td (Hello) Tj ET',
      'numbers of every shape': '1 -2 +3 .5 -.75 4. 0.0 re',
      'an array with kerning': 'BT [(A) -120 (B) 35.5 (C)] TJ ET',
      'a name with an escape': '/Name#20With#23Escapes cs',
      'nested brackets in a string': r'((a (b) c)) Tj',
      'an escaped bracket': r'(a \) not the end) Tj',
      'an escaped backslash before a bracket': r'(ends with a backslash \\) Tj',
      'a hex string': '<48656C6C6F> Tj',
      'a dictionary': '<< /Type /Thing /N 3 >> BDC',
      'a comment': '% this is a comment\n72 700 Td',
      'no trailing newline': '72 700 Td',
      'windows line endings': 'BT\r\n/F1 12 Tf\r\n(Hi) Tj\r\nET',
      'an empty stream': '',
      'only whitespace': '   \n\t  ',
    }.entries) {
      test('re-emits ${entry.key} byte for byte', () {
        final bytes = of(entry.value);

        expect(reemit(bytes, tokenizeContentStream(bytes)), bytes);
      });
    }

    // The one that matters most: the payload is not instructions, and it can
    // contain every byte there is.
    test('re-emits an inline image byte for byte', () {
      final bytes = <int>[
        ...of('q 1 0 0 1 0 0 cm BI /W 2 /H 2 /BPC 8 /CS /G ID '),
        // Data containing an operator name, a bracket, and the bytes 'EI'
        // without the whitespace that would end the image.
        0x42, 0x54, 0x28, 0x45, 0x49, 0xFF, 0x00, 0x29,
        ...of(' EI Q'),
      ];

      expect(reemit(bytes, tokenizeContentStream(bytes)), bytes);
    });

    test('re-emits every stream in the sample document', () {
      final streams = streamsIn(buildPdf(kSampleThreePage));

      expect(streams, isNotEmpty);
      for (final stream in streams) {
        expect(
          reemit(stream, tokenizeContentStream(stream)),
          stream,
          reason: latin1.decode(stream, allowInvalid: true),
        );
      }
    });

    test('re-emits a stream that ends mid-string', () {
      final bytes = of('BT (unterminated');

      expect(reemit(bytes, tokenizeContentStream(bytes)), bytes);
    });
  });

  group('tokens', () {
    test('a text object is operators and operands', () {
      final bytes = of('BT /F1 12 Tf (Hi) Tj ET');
      final tokens = tokenizeContentStream(bytes);

      expect(tokens.map((t) => t.kind), [
        ContentTokenKind.operator,
        ContentTokenKind.name,
        ContentTokenKind.number,
        ContentTokenKind.operator,
        ContentTokenKind.literalString,
        ContentTokenKind.operator,
        ContentTokenKind.operator,
      ]);
    });

    // A bracket inside a string does not end it. Counting brackets without
    // honouring the backslash turns the rest of the page into operators.
    test('an escaped bracket does not end a string', () {
      final bytes = of(r'(a \) b) Tj');
      final tokens = tokenizeContentStream(bytes);

      expect(textOf(bytes, tokens.first), r'(a \) b)');
    });

    test('brackets nest', () {
      final bytes = of('((inner)) Tj');

      expect(textOf(bytes, tokenizeContentStream(bytes).first), '((inner))');
    });

    // A backslash escapes a backslash, so the bracket after two of them DOES
    // end the string.
    test('an escaped backslash does not escape the bracket after it', () {
      final bytes = of(r'(a \\) Tj');
      final tokens = tokenizeContentStream(bytes);

      expect(textOf(bytes, tokens.first), r'(a \\)');
      expect(tokens.length, 2);
    });

    test('a hex string is one token', () {
      final bytes = of('<48656C6C6F> Tj');
      final tokens = tokenizeContentStream(bytes);

      expect(tokens.first.kind, ContentTokenKind.hexString);
      expect(textOf(bytes, tokens.first), '<48656C6C6F>');
    });

    // `<<` opens a dictionary; a single `<` opens a hex string. Reading one as
    // the other loses the rest of the stream.
    test('a dictionary is not a hex string', () {
      final bytes = of('<< /A 1 >> BDC');

      expect(
        tokenizeContentStream(bytes).first.kind,
        ContentTokenKind.dictionaryStart,
      );
    });

    test('numbers keep their sign and point', () {
      final bytes = of('-1.5 +2 .5 3.');
      final tokens = tokenizeContentStream(bytes);

      expect(tokens.map((t) => textOf(bytes, t)), ['-1.5', '+2', '.5', '3.']);
      expect(tokens.every((t) => t.kind == ContentTokenKind.number), isTrue);
    });

    // A minus with nothing numeric after it is not an operand, and treating
    // it as one swallows the operator that follows.
    test('a lone minus is not a number', () {
      final bytes = of('- Tj');

      expect(
        tokenizeContentStream(bytes).first.kind,
        isNot(ContentTokenKind.number),
      );
    });

    // A name runs to the next delimiter, escapes and all. Stopping early
    // leaves the rest of it to be read as an operator.
    test('a name runs to the delimiter', () {
      final bytes = of('/Name#20With#23Escapes cs');
      final tokens = tokenizeContentStream(bytes);

      expect(textOf(bytes, tokens.first), '/Name#20With#23Escapes');
      expect(tokens.length, 2);
    });

    test('a name ending at a bracket keeps its whole self', () {
      final bytes = of('/F1[');
      final tokens = tokenizeContentStream(bytes);

      expect(textOf(bytes, tokens.first), '/F1');
      expect(tokens[1].kind, ContentTokenKind.arrayStart);
    });

    test('a comment is a token of its own', () {
      final bytes = of('% hello\n1 0 0 1 0 0 cm');
      final tokens = tokenizeContentStream(bytes);

      expect(tokens.first.kind, ContentTokenKind.comment);
      expect(textOf(bytes, tokens.first), '% hello');
    });

    test('an inline image is one token, payload and all', () {
      final bytes = of('BI /W 1 /H 1 ID xx EI Q');
      final tokens = tokenizeContentStream(bytes);

      expect(tokens.first.kind, ContentTokenKind.inlineImage);
      expect(textOf(bytes, tokens.first), 'BI /W 1 /H 1 ID xx EI');
      expect(tokens.last.kind, ContentTokenKind.operator);
    });

    // `EI` only ends the image when whitespace comes before it. Image data
    // that happens to contain the letters - and it will, over enough images -
    // ends the token early and turns the rest of the JPEG into operators.
    test('EI inside the data does not end the image', () {
      final bytes = <int>[
        ...of('BI /W 4 /H 1 /BPC 8 /CS /G ID '),
        // 'xEI ' - the letters, followed by whitespace, but NOT preceded by
        // any. Only the byte before decides.
        0x78, 0x45, 0x49, 0x20, 0x01, 0x02,
        ...of(' EI Q'),
      ];
      final tokens = tokenizeContentStream(bytes);

      expect(tokens.first.kind, ContentTokenKind.inlineImage);
      expect(tokens.length, 2);
      expect(reemit(bytes, tokens), bytes);
      // The image ends at the LAST EI, so its data carries both bytes 1 and 2.
      expect(tokens.first.end, bytes.length - 2);
    });

    // Without this the JPEG's contents become operators, and everything after
    // the image is nonsense.
    test("an inline image's data is never read as instructions", () {
      final bytes = <int>[
        ...of('BI /W 1 /H 1 ID '),
        ...of('BT (x) Tj ET'),
        ...of(' EI Q'),
      ];
      final tokens = tokenizeContentStream(bytes);

      expect(tokens.length, 2);
      expect(tokens.first.kind, ContentTokenKind.inlineImage);
    });
  });

  group('operations', () {
    test('operands are gathered up to their operator', () {
      final bytes = of('BT /F1 12 Tf 72 700 Td (Hi) Tj ET');
      final operations = parseContentStream(bytes);

      expect(operations.map((o) => o.operator), ['BT', 'Tf', 'Td', 'Tj', 'ET']);
      expect(operations[1].operands.length, 2);
      expect(operations[2].operands.length, 2);
    });

    // The span has to cover the operands too, or replacing an operation
    // leaves its arguments behind.
    test('an operation spans its operands and its operator', () {
      final bytes = of('BT 72 700 Td ET');
      final td = parseContentStream(
        bytes,
      ).firstWhere((o) => o.operator == 'Td');

      expect(latin1.decode(bytes.sublist(td.start, td.end)), '72 700 Td');
    });

    test('an operator with no operands spans only itself', () {
      final bytes = of('BT ET');
      final bt = parseContentStream(bytes).first;

      expect(latin1.decode(bytes.sublist(bt.start, bt.end)), 'BT');
    });

    test('a comment does not become an operand', () {
      final bytes = of('72 % why\n700 Td');
      final td = parseContentStream(bytes).single;

      expect(td.operator, 'Td');
      expect(td.operands.length, 2);
    });

    test('an array operand is kept as its tokens', () {
      final bytes = of('[(A) -120 (B)] TJ');
      final tj = parseContentStream(bytes).single;

      expect(tj.operator, 'TJ');
      expect(tj.operands.map((t) => t.kind), [
        ContentTokenKind.arrayStart,
        ContentTokenKind.literalString,
        ContentTokenKind.number,
        ContentTokenKind.literalString,
        ContentTokenKind.arrayEnd,
      ]);
    });

    test('an inline image is an operation, not an operand', () {
      final bytes = of('q BI /W 1 /H 1 ID xx EI Q');
      final operations = parseContentStream(bytes);

      expect(operations.map((o) => o.operator), ['q', 'BI', 'Q']);
      expect(operations.last.operands, isEmpty);
    });

    test('the sample document parses into recognisable operators', () {
      final stream = streamsIn(buildPdf(kSampleThreePage)).first;
      final operators = parseContentStream(
        stream,
      ).map((o) => o.operator).toSet();

      expect(operators, containsAll(['BT', 'Tf', 'Td', 'Tj', 'ET']));
    });

    test('a damaged stream does not hang or throw', () {
      for (final source in [
        '((((',
        '<<<<',
        '<AB',
        'BI /W 1 ID no end',
        r'(\\',
        ')))',
        '/',
      ]) {
        expect(
          () => parseContentStream(of(source)),
          returnsNormally,
          reason: source,
        );
      }
    });

    // The property that makes tokenising terminate: every token consumes at
    // least one byte. Stated rather than reasoned about, because a sub-parser
    // that returns where it started spins forever - a parser fed arbitrary
    // files does not fail then, it freezes.
    test('every token consumes at least one byte', () {
      for (final source in [
        'BT /F1 12 Tf (Hi) Tj ET',
        '((((',
        '<<<<',
        '<AB',
        '%',
        '%\n',
        'BI /W 1 ID no end',
        r'(\\',
        ')))',
        '/',
        '- - -',
        '<',
        '>',
        '{}',
      ]) {
        final bytes = of(source);

        expect(
          tokensAdvance(bytes, tokenizeContentStream(bytes)),
          isTrue,
          reason: source,
        );
      }
    });

    test('the sample document tokenises into advancing tokens', () {
      for (final stream in streamsIn(buildPdf(kSampleThreePage))) {
        expect(tokensAdvance(stream, tokenizeContentStream(stream)), isTrue);
      }
    });
  });
}
