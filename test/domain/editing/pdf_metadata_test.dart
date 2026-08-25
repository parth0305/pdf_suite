import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';

Uint8List bytes(String s) => Uint8List.fromList(latin1.encode(s));

/// A minimal PDF with a classic xref table and an /Info dictionary.
Uint8List pdfWithInfo(String infoBody) {
  final objs = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [] /Count 0 >>',
    infoBody,
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objs.length + 1} /Root 1 0 R /Info 3 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return bytes(out.toString());
}

Uint8List pdfWithoutInfo() {
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final o in [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [] /Count 0 >>',
  ]) {
    offsets.add(out.length);
    out.write('${offsets.length} 0 obj\n$o\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 3\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return bytes(out.toString());
}

void main() {
  group('readFrom', () {
    test('reads title, author and subject', () {
      final pdf = pdfWithInfo(
        '<< /Title (Quarterly Report) /Author (A Sharma) '
        '/Subject (Finance) >>',
      );
      final meta = PdfMetadata.readFrom(pdf);

      expect(meta, isNotNull);
      expect(meta!.title, 'Quarterly Report');
      expect(meta.author, 'A Sharma');
      expect(meta.subject, 'Finance');
    });

    test('reads keywords and creator', () {
      final pdf = pdfWithInfo('<< /Keywords (q3, tax) /Creator (Folio) >>');
      final meta = PdfMetadata.readFrom(pdf)!;

      expect(meta.keywords, 'q3, tax');
      expect(meta.creator, 'Folio');
    });

    test('absent fields are null, not empty strings', () {
      final meta = PdfMetadata.readFrom(pdfWithInfo('<< /Title (Only) >>'))!;

      expect(meta.title, 'Only');
      expect(meta.author, isNull);
      expect(meta.subject, isNull);
    });

    test('a document with no /Info returns null', () {
      expect(PdfMetadata.readFrom(pdfWithoutInfo()), isNull);
    });

    test('an empty /Info returns an empty, not-null, record', () {
      final meta = PdfMetadata.readFrom(pdfWithInfo('<< >>'));
      expect(meta, isNotNull);
      expect(meta!.isEmpty, isTrue);
    });

    test('malformed input returns null rather than throwing', () {
      expect(PdfMetadata.readFrom(bytes('not a pdf at all')), isNull);
    });

    // Escaped delimiters inside a title must survive the round trip.
    test('reads a title containing escaped parentheses', () {
      final pdf = pdfWithInfo(r'<< /Title (Report \(final\)) >>');
      expect(PdfMetadata.readFrom(pdf)!.title, 'Report (final)');
    });

    test('reads a title containing an escaped backslash', () {
      final pdf = pdfWithInfo(r'<< /Title (a\\b) >>');
      expect(PdfMetadata.readFrom(pdf)!.title, r'a\b');
    });
  });

  group('appendTo', () {
    test('the appended document still ends with %%EOF', () {
      final out = const PdfMetadata(title: 'T').appendTo(pdfWithoutInfo());
      expect(latin1.decode(out).trimRight().endsWith('%%EOF'), isTrue);
    });

    test('the original bytes are preserved byte-for-byte at the front', () {
      final original = pdfWithoutInfo();
      final out = const PdfMetadata(title: 'T').appendTo(original);

      expect(out.length, greaterThan(original.length));
      expect(out.sublist(0, original.length), original);
    });

    test('round-trips through readFrom', () {
      const meta = PdfMetadata(
        title: 'Quarterly Report',
        author: 'A Sharma',
        subject: 'Finance',
        keywords: 'q3',
        creator: 'Folio',
      );
      final out = meta.appendTo(pdfWithoutInfo());
      final back = PdfMetadata.readFrom(out)!;

      expect(back.title, 'Quarterly Report');
      expect(back.author, 'A Sharma');
      expect(back.subject, 'Finance');
      expect(back.keywords, 'q3');
      expect(back.creator, 'Folio');
    });

    test('overrides an existing /Info rather than being ignored', () {
      final original = pdfWithInfo('<< /Title (Old) >>');
      final out = const PdfMetadata(title: 'New').appendTo(original);

      expect(PdfMetadata.readFrom(out)!.title, 'New');
    });

    // The sharp edge: unescaped delimiters would corrupt the file.
    test('a title containing parentheses round-trips', () {
      const meta = PdfMetadata(title: 'Report (final)');
      final back = PdfMetadata.readFrom(meta.appendTo(pdfWithoutInfo()))!;
      expect(back.title, 'Report (final)');
    });

    test('a title containing a backslash round-trips', () {
      const meta = PdfMetadata(title: r'path\to\file');
      final back = PdfMetadata.readFrom(meta.appendTo(pdfWithoutInfo()))!;
      expect(back.title, r'path\to\file');
    });

    test('an unbalanced closing parenthesis round-trips', () {
      const meta = PdfMetadata(title: 'oops )');
      final back = PdfMetadata.readFrom(meta.appendTo(pdfWithoutInfo()))!;
      expect(back.title, 'oops )');
    });

    test('empty metadata appends nothing', () {
      final original = pdfWithoutInfo();
      expect(const PdfMetadata().appendTo(original), original);
    });

    test('appending to a document with no startxref throws', () {
      expect(
        () => const PdfMetadata(title: 'T').appendTo(bytes('garbage')),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
