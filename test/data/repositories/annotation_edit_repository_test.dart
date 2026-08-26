import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_edit_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';

const annotatedPdf =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
    '/Annots [7 0 R 8 0 R] >>\nendobj\n'
    '7 0 obj\n<< /Type /Annot /Subtype /Square /Rect [10 20 50 80] '
    '/C [0 0 1] /BS << /W 3 >> >>\nendobj\n'
    '8 0 obj\n<< /Type /Annot /Subtype /Circle /Rect [60 20 100 80] '
    '/C [1 0 0] /BS << /W 2 >> >>\nendobj\n'
    'xref\n0 9\n0000000000 65535 f \n'
    'trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

void main() {
  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late DocumentWriter writer;
  late AnnotationEditRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('annot_edit');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    writer = DocumentWriter(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = AnnotationEditRepositoryImpl(library: library, documents: writer);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Uint8List pdf() => Uint8List.fromList(annotatedPdf.codeUnits);

  Future<int> folioCreated() async =>
      (await writer.store(pdf(), 'Folio.pdf')).id;

  Future<int> imported() async {
    final f = File('${root.path}/outside.pdf')..writeAsBytesSync(pdf());
    return (await library.importFile(f.path, displayName: 'Outside.pdf')).id;
  }

  test('loads the annotations already in the document', () async {
    final found = await subject.load(await folioCreated());

    expect(found.map((a) => a.subtype), ['Square', 'Circle']);
  });

  test('a Folio-created document is edited in place', () async {
    final id = await folioCreated();

    final saved = await subject.save(
      documentId: id,
      deleted: {7},
      restyled: const {},
      moved: const {},
    );

    expect(saved.id, id, reason: 'the same library row');
    expect(await library.all(), hasLength(1));
  });

  test('an imported document produces a new document', () async {
    final id = await imported();

    final saved = await subject.save(
      documentId: id,
      deleted: {7},
      restyled: const {},
      moved: const {},
    );

    expect(saved.id, isNot(id));
    expect(await library.all(), hasLength(2));
  });

  test('an imported source is left byte-identical', () async {
    final id = await imported();
    final before = await File(
      await library.resolveReadablePath(
        (await library.all()).firstWhere((d) => d.id == id),
      ),
    ).readAsBytes();

    await subject.save(
      documentId: id,
      deleted: {7},
      restyled: const {},
      moved: const {},
    );

    final after = await File(
      await library.resolveReadablePath(
        (await library.all()).firstWhere((d) => d.id == id),
      ),
    ).readAsBytes();
    expect(after, before);
  });

  test('the edit is present in the saved bytes', () async {
    final id = await folioCreated();
    final saved = await subject.save(
      documentId: id,
      deleted: {7},
      restyled: const {},
      moved: const {},
    );

    final text = await File(
      await library.resolveReadablePath(saved),
    ).readAsString();
    expect(text.lastIndexOf('/Annots [8 0 R]'), greaterThan(0));
  });

  test('saving nothing is rejected before anything is written', () async {
    final id = await folioCreated();

    await expectLater(
      subject.save(
        documentId: id,
        deleted: const {},
        restyled: const {},
        moved: const {},
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await library.all(), hasLength(1));
  });
}
