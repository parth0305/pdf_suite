import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_edit_repository_impl.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
// pdfrx exports its own PdfPoint; the only one this test wants is Folio's.
import 'package:pdfrx/pdfrx.dart' hide PdfPoint;

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late DocumentWriter writer;
  late AnnotationRepositoryImpl annotations;
  late AnnotationEditRepositoryImpl edits;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('annot_edit_flow');
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
    annotations = AnnotationRepositoryImpl(library: library, documents: writer);
    edits = AnnotationEditRepositoryImpl(library: library, documents: writer);
    engine = PdfrxEngine();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<List<int>> render(LibraryDocument d) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final px = (await engine.renderPage(
      h,
      0,
      targetWidthPx: 400,
      targetHeightPx: 566,
    )).bgraPixels;
    await engine.close(h);
    return px;
  }

  int diff(List<int> a, List<int> b) {
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) n++;
    }
    return n;
  }

  Future<LibraryDocument> reload(int id) async =>
      (await library.all()).firstWhere((d) => d.id == id);

  Future<String> hashOf(LibraryDocument d) async => sha256
      .convert(await File(await library.resolveReadablePath(d)).readAsBytes())
      .toString();

  /// Three well-separated shapes on page 0, saved through the real writer.
  Future<LibraryDocument> withThree(String name) async {
    final src = await library.importFile(
      await fixturePath('sample_3page.pdf'),
      displayName: name,
    );
    return annotations.saveAnnotations(
      sourceDocumentId: src.id,
      annotations: const [
        DrawingAnnotation(
          kind: DrawingKind.rectangle,
          pageIndex: 0,
          points: [PdfPoint(60, 600), PdfPoint(200, 700)],
          strokeWidth: 4,
        ),
        DrawingAnnotation(
          kind: DrawingKind.rectangle,
          pageIndex: 0,
          points: [PdfPoint(220, 600), PdfPoint(360, 700)],
          colorArgb: 0xFFD32F2F,
          strokeWidth: 4,
        ),
        DrawingAnnotation(
          kind: DrawingKind.rectangle,
          pageIndex: 0,
          points: [PdfPoint(380, 600), PdfPoint(520, 700)],
          colorArgb: 0xFF1976D2,
          strokeWidth: 4,
        ),
      ],
    );
  }

  group('annotation edit flow', () {
    test('the saved annotations can be read back', () async {
      final doc = await withThree('Three.pdf');
      final found = await edits.load(doc.id);

      expect(found, hasLength(3));
      expect(found.every((a) => a.subtype == 'Square'), isTrue);
      expect(found.every((a) => a.restylable), isTrue);
    });

    // The gate: a deleted annotation must stop RENDERING, not merely lose a
    // reference in bytes nobody looked at.
    test('deleting one annotation stops it drawing', () async {
      final doc = await withThree('Delete.pdf');
      final before = await render(doc);
      final target = (await edits.load(doc.id))[1];

      await edits.save(
        documentId: doc.id,
        deleted: {target.objectNumber},
        restyled: const {},
      );
      final after = await render(await reload(doc.id));

      expect(
        diff(before, after),
        greaterThan(200),
        reason: 'the deleted annotation must stop rendering',
      );
    });

    test('the annotations that were not deleted still draw', () async {
      final doc = await withThree('Survivors.pdf');
      final plain = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Plain.pdf',
      );
      final blank = await render(plain);
      final target = (await edits.load(doc.id))[1];

      await edits.save(
        documentId: doc.id,
        deleted: {target.objectNumber},
        restyled: const {},
      );
      final after = await render(await reload(doc.id));

      expect(
        diff(blank, after),
        greaterThan(400),
        reason: 'two annotations should still be drawn',
      );
    });

    test('restyling changes rendered pixels', () async {
      final doc = await withThree('Restyle.pdf');
      final before = await render(doc);
      final target = (await edits.load(doc.id)).first;

      await edits.save(
        documentId: doc.id,
        deleted: const {},
        restyled: {
          target.objectNumber: const AnnotationStyle(
            colorArgb: 0xFFD32F2F,
            strokeWidth: 8,
          ),
        },
      );
      final after = await render(await reload(doc.id));

      expect(diff(before, after), greaterThan(200));
    });

    // A restyle that moves an annotation corrupts the document invisibly.
    test('restyling does not move the annotation', () async {
      final doc = await withThree('Stable.pdf');
      final target = (await edits.load(doc.id)).first;

      await edits.save(
        documentId: doc.id,
        deleted: const {},
        restyled: {
          target.objectNumber: const AnnotationStyle(
            colorArgb: 0xFF388E3C,
            strokeWidth: 6,
          ),
        },
      );

      final after = (await edits.load(
        doc.id,
      )).firstWhere((a) => a.objectNumber == target.objectNumber);
      expect(after.rectPt.left, target.rectPt.left);
      expect(after.rectPt.bottom, target.rectPt.bottom);
      expect(after.rectPt.right, target.rectPt.right);
      expect(after.rectPt.top, target.rectPt.top);
    });

    test('a Folio-created document is edited in place and renders', () async {
      final doc = await withThree('InPlace.pdf');
      final before = await render(doc);
      final target = (await edits.load(doc.id)).first;

      final saved = await edits.save(
        documentId: doc.id,
        deleted: {target.objectNumber},
        restyled: const {},
      );

      expect(saved.id, doc.id, reason: 'one library row, not two');
      expect(diff(before, await render(saved)), greaterThan(200));
    });

    test('an imported document is left byte-identical', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Imported.pdf',
      );
      final before = await hashOf(src);

      // Nothing to delete in a plain document, so this asserts the guard.
      await expectLater(
        edits.save(documentId: src.id, deleted: const {}, restyled: const {}),
        throwsA(isA<ArgumentError>()),
      );
      expect(await hashOf(await reload(src.id)), before);
    });

    // Delete must work on annotations Folio did not write.
    test('an annotation Folio did not write can still be deleted', () async {
      final doc = await withThree('Foreign.pdf');
      final bytes = await File(
        await library.resolveReadablePath(doc),
      ).readAsBytes();

      // Inject a /Stamp - a subtype Folio never produces - and reference it.
      final text = latin1.decode(bytes, allowInvalid: true);
      final refs = RegExp(r'/Annots \[([^\]]*)\]').allMatches(text).last;
      final injected =
          '$text'
          '99 0 obj\n<< /Type /Annot /Subtype /Stamp /Rect [10 10 60 60] >>\n'
          'endobj\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
          '/Annots [${refs.group(1)} 99 0 R] >>\nendobj\n'
          'trailer\n<< /Size 120 /Root 1 0 R /Prev 9 >>\n'
          'startxref\n9\n%%EOF\n';

      final f = File('${root.path}/foreign.pdf')
        ..writeAsBytesSync(latin1.encode(injected));
      final withStamp = await library.importFile(
        f.path,
        displayName: 'WithStamp.pdf',
      );

      final loaded = await edits.load(withStamp.id);
      final stamp = loaded.firstWhere((a) => a.subtype == 'Stamp');
      expect(
        stamp.restylable,
        isFalse,
        reason: 'Folio cannot regenerate a Stamp appearance',
      );

      final saved = await edits.save(
        documentId: withStamp.id,
        deleted: {stamp.objectNumber},
        restyled: const {},
      );

      final after = await edits.load(saved.id);
      expect(after.any((a) => a.subtype == 'Stamp'), isFalse);
    });

    test('metadata survives an edit', () async {
      final src = await library.importFile(
        await fixturePath('with_metadata.pdf'),
        displayName: 'Meta.pdf',
      );
      final annotated = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: const [
          DrawingAnnotation(
            kind: DrawingKind.rectangle,
            pageIndex: 0,
            points: [PdfPoint(60, 600), PdfPoint(200, 700)],
            strokeWidth: 4,
          ),
        ],
      );
      final before = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(annotated)).readAsBytes(),
      )!;

      final target = (await edits.load(annotated.id)).first;
      final saved = await edits.save(
        documentId: annotated.id,
        deleted: {target.objectNumber},
        restyled: const {},
      );

      final after = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(saved)).readAsBytes(),
      )!;
      expect(after.title, before.title);
      expect(after.author, before.author);
    });
  });
}
