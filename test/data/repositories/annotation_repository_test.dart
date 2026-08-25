import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_types.dart';

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late AnnotationRepositoryImpl subject;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('annot_repo');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
    subject = AnnotationRepositoryImpl(
      library: library,
      documents: DocumentWriter(
        library: library,
        writer: SafeFileWriter(),
        libraryRoot: sandbox,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// A classic-xref PDF carrying metadata, so both concerns can be asserted.
  Future<int> seed() async {
    final f = File('${sandbox.path}/src.pdf');
    f.writeAsStringSync(
      '%PDF-1.4\n'
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\nendobj\n'
      '4 0 obj\n<< /Title (Kept Title) /Author (A Sharma) >>\nendobj\n'
      'xref\n0 5\n0000000000 65535 f \n'
      'trailer\n<< /Size 5 /Root 1 0 R /Info 4 0 R >>\n'
      'startxref\n9\n%%EOF\n',
    );
    final doc = await library.importFile(f.path, displayName: 'Contract.pdf');
    return doc.id;
  }

  TextMarkup markup() => const TextMarkup(
    kind: MarkupKind.highlight,
    pageIndex: 0,
    quads: [TextRect(left: 60, top: 712, right: 120, bottom: 700)],
  );

  test('creates a new document and leaves the source byte-identical', () async {
    final id = await seed();
    final sourcePath = await library.resolveReadablePath(
      (await library.all()).single,
    );
    final before = await File(sourcePath).readAsBytes();

    final out = await subject.saveMarkup(
      sourceDocumentId: id,
      markups: [markup()],
    );

    expect(out.displayName, 'Contract (edited).pdf');
    expect(await library.all(), hasLength(2));
    expect(await File(sourcePath).readAsBytes(), before);
  });

  test('the output carries the annotation', () async {
    final id = await seed();
    final out = await subject.saveMarkup(
      sourceDocumentId: id,
      markups: [markup()],
    );

    final text = await File(
      await library.resolveReadablePath(out),
    ).readAsString();
    expect(text, contains('/Subtype /Highlight'));
  });

  // The SP-2b regression guard, on the new write path.
  test('metadata survives the annotation save', () async {
    final id = await seed();
    final out = await subject.saveMarkup(
      sourceDocumentId: id,
      markups: [markup()],
    );

    final meta = PdfMetadata.readFrom(
      await File(await library.resolveReadablePath(out)).readAsBytes(),
    );
    expect(meta?.title, 'Kept Title');
    expect(meta?.author, 'A Sharma');
  });

  test('an empty markup list is rejected before anything is written', () async {
    final id = await seed();

    await expectLater(
      subject.saveMarkup(sourceDocumentId: id, markups: const []),
      throwsA(isA<ArgumentError>()),
    );
    expect(await library.all(), hasLength(1));
  });
}
