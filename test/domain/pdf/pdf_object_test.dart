import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

import '../../../scripts/pdf_fixture_builder.dart';

List<int> bytesOf(String s) => latin1.encode(s);

void main() {
  test('finds every object with its number and generation', () {
    final objects = parsePdfObjects(
      bytesOf(
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        '7 2 obj\n<< /Type /Annot >>\nendobj\n',
      ),
    );

    expect(objects.map((o) => o.number), [1, 7]);
    expect(objects.map((o) => o.generation), [0, 2]);
  });

  test('captures the body between obj and endobj', () {
    final objects = parsePdfObjects(
      bytesOf('1 0 obj\n<< /Type /Catalog >>\nendobj\n'),
    );

    expect(latin1.decode(objects.single.body), contains('/Type /Catalog'));
    expect(latin1.decode(objects.single.body), isNot(contains('endobj')));
  });

  // Binary stream data can contain the bytes `endobj`. Searching for that word
  // ends the object in the middle of its own stream and corrupts everything
  // after it.
  test('a stream containing the bytes endobj does not end the object', () {
    const payload = 'AAendobjBB';
    final objects = parsePdfObjects(
      bytesOf(
        '4 0 obj\n<< /Length ${payload.length} >>\nstream\n'
        '$payload\nendstream\nendobj\n'
        '5 0 obj\n<< /Type /Page >>\nendobj\n',
      ),
    );

    expect(objects.map((o) => o.number), [4, 5]);
    expect(latin1.decode(objects.first.body), contains(payload));
  });

  test('handles a stream whose data begins after CRLF', () {
    const payload = 'hello';
    final objects = parsePdfObjects(
      bytesOf(
        '4 0 obj\n<< /Length ${payload.length} >>\nstream\r\n'
        '$payload\r\nendstream\nendobj\n',
      ),
    );

    expect(objects, hasLength(1));
    expect(latin1.decode(objects.single.body), contains(payload));
  });

  test('an object with no stream is unaffected', () {
    final objects = parsePdfObjects(
      bytesOf('3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] >>\nendobj\n'),
    );

    expect(latin1.decode(objects.single.body), contains('/MediaBox'));
  });

  test('a truncated object is skipped rather than throwing', () {
    final objects = parsePdfObjects(bytesOf('9 0 obj\n<< /Type /Page >>\n'));
    expect(objects, isEmpty);
  });

  // A real document, built by the same pure builder the fixtures use rather
  // than read from disk: a relative path depends on the working directory and
  // does not survive Windows CI.
  test('reads every object out of a real document', () {
    final objects = parsePdfObjects(buildPdf(kSampleThreePage));

    expect(objects, hasLength(9));
    expect(
      objects.map((o) => o.number).toSet().length,
      9,
      reason: 'every object number is distinct',
    );
    expect(
      objects.any((o) => latin1.decode(o.body).contains('/Type /Catalog')),
      isTrue,
    );
  });
}
