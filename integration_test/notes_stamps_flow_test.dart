// Integration tests run against a real device, and the aggregate entrypoint
// keeps one app process alive across every suite. The runner's default 30s per
// test is a benchmark, not a pathology bound: a loop over six presets on a
// loaded emulator legitimately exceeds it. Five minutes means "something is
// genuinely wrong", which is the only thing a timeout should assert.
@Timeout(Duration(minutes: 5))
library;

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
    root = await Directory.systemTemp.createTemp('notes_flow');
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

  Future<LibraryDocument> seed(String name) async => library.importFile(
    await fixturePath('sample_3page.pdf'),
    displayName: name,
  );

  const note = StickyNote(
    pageIndex: 0,
    anchorPt: PdfPoint(120, 700),
    contents: 'Check this clause',
  );

  group('notes and stamps flow', () {
    test('a placed note draws its icon', () async {
      final src = await seed('Note.pdf');
      final before = await render(src);

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [note],
      );

      expect(diff(before, await render(out)), greaterThan(200));
    });

    test('a placed stamp draws', () async {
      final src = await seed('Stamp.pdf');
      final before = await render(src);

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          const Stamp(
            preset: StampPreset.approved,
            pageIndex: 0,
            anchorPt: PdfPoint(120, 600),
          ),
        ],
      );

      expect(diff(before, await render(out)), greaterThan(500));
    });

    test('every preset renders', () async {
      for (final preset in StampPreset.values) {
        final src = await seed('S-${preset.name}.pdf');
        final before = await render(src);

        final out = await annotations.saveAnnotations(
          sourceDocumentId: src.id,
          annotations: [
            Stamp(
              preset: preset,
              pageIndex: 0,
              anchorPt: const PdfPoint(80, 600),
            ),
          ],
        );

        expect(
          diff(before, await render(out)),
          greaterThan(500),
          reason: '${preset.name} must be drawn',
        );
      }
    });

    test('a note and a stamp save together', () async {
      final src = await seed('Both.pdf');

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          note,
          const Stamp(
            preset: StampPreset.urgent,
            pageIndex: 0,
            anchorPt: PdfPoint(120, 600),
          ),
        ],
      );

      final text = await File(
        await library.resolveReadablePath(out),
      ).readAsString();
      expect(text, contains('/Subtype /Text'));
      expect(text, contains('/Subtype /Stamp'));

      final h = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      expect(h.pageCount, 3);
      await engine.close(h);
    });

    test("editing a note's text changes /Contents, not /Rect", () async {
      final src = await seed('Edit.pdf');
      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [note],
      );

      final target = (await edits.load(out.id)).single;
      final rectBefore = target.rectPt;

      final saved = await edits.save(
        documentId: out.id,
        deleted: const {},
        restyled: {
          target.objectNumber: const AnnotationStyle(
            colorArgb: 0xFFFFC107,
            strokeWidth: 2,
            contents: 'Corrected wording',
          ),
        },
        moved: const {},
      );

      final after = (await edits.load(saved.id)).single;
      expect(
        (after.reconstructed! as StickyNote).contents,
        'Corrected wording',
      );
      expect(after.rectPt.left, rectBefore.left);
      expect(after.rectPt.top, rectBefore.top);
    });

    test('deleting a note removes it', () async {
      final src = await seed('Remove.pdf');
      final plain = await render(src);
      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [note],
      );

      final target = (await edits.load(out.id)).single;
      final cleaned = await edits.save(
        documentId: out.id,
        deleted: {target.objectNumber},
        restyled: const {},
        moved: const {},
      );

      expect(diff(plain, await render(cleaned)), lessThan(200));
    });

    test('the source document is byte-identical afterwards', () async {
      final src = await seed('Untouched.pdf');
      final path = await library.resolveReadablePath(src);
      final before = sha256.convert(await File(path).readAsBytes()).toString();

      await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [note],
      );

      expect(sha256.convert(await File(path).readAsBytes()).toString(), before);
    });
  });
}
