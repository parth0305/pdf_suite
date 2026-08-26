import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';

void main() {
  // A long, repetitive content stream is exactly what an ink appearance looks
  // like, and exactly what deflate is good at.
  test('a long stream is compressed and declares its filter', () {
    final content = List.generate(
      200,
      (i) => '${i % 10} ${i % 7} m 10 10 l S',
    ).join('\n');

    final body = pdfStreamBody(content);

    expect(body.bytes.length, lessThan(content.length));
    expect(body.filter, contains('/Filter /FlateDecode'));
  });

  // Deflate has overhead. A 40-byte appearance stream comes out BIGGER, and
  // compressing unconditionally would make Folio's output larger.
  test('a short stream is left raw', () {
    const content = '0 0 0 RG 2 w 10 10 m 20 20 l S';

    final body = pdfStreamBody(content);

    expect(body.bytes, latin1.encode(content));
    expect(body.filter, isEmpty);
  });

  test('an empty stream is left raw', () {
    final body = pdfStreamBody('');

    expect(body.bytes, isEmpty);
    expect(body.filter, isEmpty);
  });

  // Whatever it decides, the bytes it returns are the bytes /Length describes.
  test('the returned bytes are what a caller should measure', () {
    final long = pdfStreamBody(List.filled(500, 'q 1 0 0 RG Q').join('\n'));
    final short = pdfStreamBody('q Q');

    expect(long.bytes, isNotEmpty);
    expect(short.bytes, latin1.encode('q Q'));
  });

  test('compressed bytes inflate back to the original content', () {
    final content = List.filled(300, '10 20 m 30 40 l S').join('\n');
    final body = pdfStreamBody(content);

    expect(body.filter, isNotEmpty, reason: 'this one should compress');
    expect(latin1.decode(ZLibCodec().decode(body.bytes)), content);
  });
}
