import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/watermark/page_geometry.dart';

typedef ParsedPage = ({PdfObjectIndex index, PdfPageObject page});

ParsedPage parse(String pdf) => (
  index: PdfObjectIndex.parse(pdf),
  page: PdfObjectReader.parse(pdf).pageAt(0)!,
);

void main() {
  test('reads a /MediaBox on the page itself', () {
    const pdf =
        '%PDF-1.4\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\n'
        'endobj\n';
    final p = parse(pdf);

    final box = mediaBoxOf(p.index, p.page);
    expect(box.right, 595);
    expect(box.top, 842);
  });

  // /MediaBox is inheritable. Reading only the page dictionary centres a
  // watermark off-page on exactly the documents that rely on inheritance.
  test('inherits /MediaBox from the /Pages node', () {
    const pdf =
        '%PDF-1.4\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 '
        '/MediaBox [0 0 612 792] >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
    final p = parse(pdf);

    final box = mediaBoxOf(p.index, p.page);
    expect(box.right, 612);
    expect(box.top, 792);
  });

  test('the page own value wins over the inherited one', () {
    const pdf =
        '%PDF-1.4\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 '
        '/MediaBox [0 0 612 792] >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\n'
        'endobj\n';
    final p = parse(pdf);

    expect(mediaBoxOf(p.index, p.page).right, 595);
  });

  test('follows more than one level of /Parent', () {
    const pdf =
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Pages /Kids [2 0 R] /Count 1 '
        '/MediaBox [0 0 400 400] >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Parent 1 0 R /Kids [3 0 R] /Count 1 >>\n'
        'endobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
    final p = parse(pdf);

    expect(mediaBoxOf(p.index, p.page).right, 400);
  });

  test('honours a non-zero origin', () {
    const pdf =
        '%PDF-1.4\n'
        '3 0 obj\n<< /Type /Page /MediaBox [10 20 610 812] >>\nendobj\n';
    final p = parse(pdf);

    final box = mediaBoxOf(p.index, p.page);
    expect(box.left, 10);
    expect(box.bottom, 20);
  });

  // A document this malformed will still render; refusing to save because we
  // could not find a page size would help nobody.
  test('falls back to US Letter when there is no /MediaBox anywhere', () {
    const pdf = '%PDF-1.4\n3 0 obj\n<< /Type /Page >>\nendobj\n';
    final p = parse(pdf);

    final box = mediaBoxOf(p.index, p.page);
    expect(box.right, 612);
    expect(box.top, 792);
  });

  // A /Parent cycle in a damaged document must not hang the app.
  test('a /Parent cycle terminates', () {
    const pdf =
        '%PDF-1.4\n'
        '2 0 obj\n<< /Type /Pages /Parent 3 0 R /Kids [3 0 R] >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
    final p = parse(pdf);

    expect(mediaBoxOf(p.index, p.page).right, 612);
  });
}
