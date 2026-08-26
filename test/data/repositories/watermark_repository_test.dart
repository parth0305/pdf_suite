import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/watermark_repository_impl.dart';
import 'package:folio/domain/watermark/watermark.dart';

const onePage =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n'
    '4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n'
    'xref\n0 5\n0000000000 65535 f \n'
    'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

void main() {
  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late WatermarkRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wm');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = WatermarkRepositoryImpl(
      library: library,
      documents: DocumentWriter(
        library: library,
        writer: SafeFileWriter(),
        libraryRoot: root,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<int> seed() async {
    final f = File('${root.path}/in.pdf')
      ..writeAsBytesSync(Uint8List.fromList(onePage.codeUnits));
    return (await library.importFile(f.path, displayName: 'Deed.pdf')).id;
  }

  test('produces a new document', () async {
    final id = await seed();

    final out = await subject.apply(id, const Watermark(text: 'DRAFT'));

    expect(out.id, isNot(id));
    expect(await library.all(), hasLength(2));
  });

  // Watermarking is not an edit in place, whatever the document's provenance.
  test('the source document is byte-identical afterwards', () async {
    final id = await seed();
    final src = (await library.all()).firstWhere((d) => d.id == id);
    final path = await library.resolveReadablePath(src);
    final before = await File(path).readAsBytes();

    await subject.apply(id, const Watermark(text: 'DRAFT'));

    expect(await File(path).readAsBytes(), before);
  });

  test('the watermark text reaches the new document', () async {
    final id = await seed();
    final out = await subject.apply(id, const Watermark(text: 'DRAFT'));

    final text = await File(
      await library.resolveReadablePath(out),
    ).readAsString();
    expect(text, contains('(DRAFT) Tj'));
  });

  test('empty text is rejected before anything is written', () async {
    final id = await seed();

    await expectLater(
      subject.apply(id, const Watermark(text: '  ')),
      throwsA(isA<ArgumentError>()),
    );
    expect(await library.all(), hasLength(1));
  });
}
