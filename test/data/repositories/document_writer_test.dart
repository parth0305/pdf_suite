import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late DocumentWriter subject;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('doc_writer');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
    subject = DocumentWriter(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// A classic-xref PDF, so metadata can actually be appended to it.
  Uint8List pdf() => Uint8List.fromList(
    '%PDF-1.4\n'
            '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
            '2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n'
            'xref\n0 3\n0000000000 65535 f \n'
            'trailer\n<< /Size 3 /Root 1 0 R >>\n'
            'startxref\n9\n%%EOF\n'
        .codeUnits,
  );

  test('stores bytes as a new library document', () async {
    final doc = await subject.store(pdf(), 'Out.pdf');

    expect(doc.displayName, 'Out.pdf');
    expect(await library.all(), hasLength(1));
    expect(File(await library.resolveReadablePath(doc)).existsSync(), isTrue);
  });

  test('identical bytes are content-addressed to the same file', () async {
    final a = await subject.store(pdf(), 'A.pdf');
    final b = await subject.store(pdf(), 'B.pdf');

    expect(
      await library.resolveReadablePath(a),
      await library.resolveReadablePath(b),
    );
    expect(await library.all(), hasLength(2), reason: 'two entries, one file');
  });

  // The SP-2b regression guard: any caller that skips metadata loses it.
  test('re-attaches metadata when supplied', () async {
    const meta = PdfMetadata(title: 'Kept', author: 'A Sharma');
    final doc = await subject.store(pdf(), 'Out.pdf', metadata: meta);

    final bytes = await File(
      await library.resolveReadablePath(doc),
    ).readAsBytes();
    final back = PdfMetadata.readFrom(bytes);

    expect(back?.title, 'Kept');
    expect(back?.author, 'A Sharma');
  });

  test('a document that cannot be patched is still stored', () async {
    // No startxref, so appendTo throws; the write must still succeed.
    final junk = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
    const meta = PdfMetadata(title: 'Ignored');

    final doc = await subject.store(junk, 'Out.pdf', metadata: meta);
    expect(await library.all(), hasLength(1));
    expect(File(await library.resolveReadablePath(doc)).existsSync(), isTrue);
  });

  test('empty metadata is a no-op, not an error', () async {
    final doc = await subject.store(
      pdf(),
      'Out.pdf',
      metadata: const PdfMetadata(),
    );
    expect(File(await library.resolveReadablePath(doc)).existsSync(), isTrue);
  });
}
