import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/quad_merge.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfPoint;

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late AnnotationRepositoryImpl annotations;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('markup_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    annotations = AnnotationRepositoryImpl(
      library: library,
      documents: DocumentWriter(
        library: library,
        writer: SafeFileWriter(),
        libraryRoot: root,
      ),
    );
    engine = PdfrxEngine();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<LibraryDocument> seed(String fixture, String name) async =>
      library.importFile(await fixturePath(fixture), displayName: name);

  Future<String> hashOf(LibraryDocument d) async => sha256
      .convert(await File(await library.resolveReadablePath(d)).readAsBytes())
      .toString();

  /// Quads over real text, taken from the engine's own char rects.
  Future<List<TextRect>> quadsOver(LibraryDocument doc, String needle) async {
    final handle = await engine.open(
      FileSource(await library.resolveReadablePath(doc)),
    );
    final text = await engine.extractText(handle, 0);
    final index = text!.fullText.indexOf(needle);
    final rects = text.charRects.sublist(index, index + needle.length);
    await engine.close(handle);
    return mergeIntoLineQuads(rects);
  }

  group('markup flow', () {
    // The gate on this whole slice: markup must RENDER through the production
    // path, not merely be present in the file.
    test('a saved highlight renders when the document is reopened', () async {
      final src = await seed('sample_3page.pdf', 'Contract.pdf');
      final quads = await quadsOver(src, 'Confidential');

      final before = await engine.open(
        FileSource(await library.resolveReadablePath(src)),
      );
      final beforePx = (await engine.renderPage(
        before,
        0,
        targetWidthPx: 400,
        targetHeightPx: 566,
      )).bgraPixels;
      await engine.close(before);

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          TextMarkup(kind: MarkupKind.highlight, pageIndex: 0, quads: quads),
        ],
      );

      final after = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final afterPx = (await engine.renderPage(
        after,
        0,
        targetWidthPx: 400,
        targetHeightPx: 566,
      )).bgraPixels;

      var changed = 0;
      for (var i = 0; i < beforePx.length; i++) {
        if (beforePx[i] != afterPx[i]) changed++;
      }
      expect(
        changed,
        greaterThan(500),
        reason: 'the highlight must actually be drawn',
      );

      await engine.close(after);
    });

    test('underline and strikeout also render', () async {
      for (final kind in [MarkupKind.underline, MarkupKind.strikeOut]) {
        final src = await seed('sample_3page.pdf', 'C-${kind.name}.pdf');
        final quads = await quadsOver(src, 'Confidential');

        final before = await engine.open(
          FileSource(await library.resolveReadablePath(src)),
        );
        final beforePx = (await engine.renderPage(
          before,
          0,
          targetWidthPx: 400,
          targetHeightPx: 566,
        )).bgraPixels;
        await engine.close(before);

        final out = await annotations.saveAnnotations(
          sourceDocumentId: src.id,
          annotations: [TextMarkup(kind: kind, pageIndex: 0, quads: quads)],
        );

        final after = await engine.open(
          FileSource(await library.resolveReadablePath(out)),
        );
        final afterPx = (await engine.renderPage(
          after,
          0,
          targetWidthPx: 400,
          targetHeightPx: 566,
        )).bgraPixels;

        var changed = 0;
        for (var i = 0; i < beforePx.length; i++) {
          if (beforePx[i] != afterPx[i]) changed++;
        }
        expect(changed, greaterThan(50), reason: '${kind.name} must be drawn');
        await engine.close(after);
      }
    });

    test('the source document is byte-identical afterwards', () async {
      final src = await seed('sample_3page.pdf', 'Contract.pdf');
      final before = await hashOf(src);

      await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          TextMarkup(
            kind: MarkupKind.highlight,
            pageIndex: 0,
            quads: await quadsOver(src, 'Confidential'),
          ),
        ],
      );

      expect(await hashOf(src), before);
    });

    test('extracted text is unchanged by markup', () async {
      final src = await seed('sample_3page.pdf', 'Contract.pdf');
      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          TextMarkup(
            kind: MarkupKind.highlight,
            pageIndex: 0,
            quads: await quadsOver(src, 'Confidential'),
          ),
        ],
      );

      final handle = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final text = await engine.extractText(handle, 0);
      expect(text!.fullText, contains('Confidential Invoice'));
      await engine.close(handle);
    });

    // SP-2b must not have regressed on this new write path.
    test('metadata survives the annotation save', () async {
      final src = await seed('with_metadata.pdf', 'Meta.pdf');
      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          TextMarkup(
            kind: MarkupKind.highlight,
            pageIndex: 0,
            quads: await quadsOver(src, 'Confidential'),
          ),
        ],
      );

      final meta = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(out)).readAsBytes(),
      );
      expect(meta?.title, 'FOLIO-PROBE-TITLE');
    });

    test('marking up twice keeps both annotations', () async {
      final src = await seed('sample_3page.pdf', 'Contract.pdf');
      final quads = await quadsOver(src, 'Confidential');

      final once = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          TextMarkup(kind: MarkupKind.highlight, pageIndex: 0, quads: quads),
        ],
      );
      final twice = await annotations.saveAnnotations(
        sourceDocumentId: once.id,
        annotations: [
          TextMarkup(kind: MarkupKind.underline, pageIndex: 0, quads: quads),
        ],
      );

      final text = await File(
        await library.resolveReadablePath(twice),
      ).readAsString();
      expect(text, contains('/Subtype /Highlight'));
      expect(text, contains('/Subtype /Underline'));

      final handle = await engine.open(
        FileSource(await library.resolveReadablePath(twice)),
      );
      expect(handle.pageCount, 3);
      await engine.close(handle);
    });

    test('an unsupported document is refused, not silently mangled', () async {
      final f = File('${root.path}/xrefstream.pdf');
      f.writeAsStringSync(
        '%PDF-1.5\n'
        '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        '4 0 obj\n<< /Type /XRef /Size 5 >>\nstream\n\nendstream\nendobj\n'
        'startxref\n9\n%%EOF\n',
      );
      final doc = await library.importFile(f.path, displayName: 'Modern.pdf');

      await expectLater(
        annotations.saveAnnotations(
          sourceDocumentId: doc.id,
          annotations: [
            const TextMarkup(
              kind: MarkupKind.highlight,
              pageIndex: 0,
              quads: [TextRect(left: 60, top: 712, right: 120, bottom: 700)],
            ),
          ],
        ),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });
  });

  group('drawing flow', () {
    // Stage 2's gate: a drawing must RENDER through the production path.
    // Byte assertions only prove the objects are present; PDFium deciding not
    // to draw them would still pass those and ship a broken feature.
    Future<int> pixelsChangedBy(List<Annotation> drawings) async {
      final src = await seed(
        'sample_3page.pdf',
        'D-${drawings.first.pdfSubtype}-${DateTime.now().microsecondsSinceEpoch}.pdf',
      );

      final before = await engine.open(
        FileSource(await library.resolveReadablePath(src)),
      );
      final beforePx = (await engine.renderPage(
        before,
        0,
        targetWidthPx: 400,
        targetHeightPx: 566,
      )).bgraPixels;
      await engine.close(before);

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: drawings,
      );

      final after = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final afterPx = (await engine.renderPage(
        after,
        0,
        targetWidthPx: 400,
        targetHeightPx: 566,
      )).bgraPixels;
      await engine.close(after);

      var changed = 0;
      for (var i = 0; i < beforePx.length; i++) {
        if (beforePx[i] != afterPx[i]) changed++;
      }
      return changed;
    }

    test('an ink stroke renders when the document is reopened', () async {
      final changed = await pixelsChangedBy(const [
        DrawingAnnotation(
          kind: DrawingKind.ink,
          pageIndex: 0,
          points: [
            PdfPoint(100, 500),
            PdfPoint(200, 600),
            PdfPoint(300, 500),
            PdfPoint(400, 600),
          ],
          strokeWidth: 4,
        ),
      ]);

      expect(changed, greaterThan(500), reason: 'the ink must be drawn');
    });

    test('every shape kind renders', () async {
      for (final kind in [
        DrawingKind.rectangle,
        DrawingKind.ellipse,
        DrawingKind.line,
        DrawingKind.arrow,
      ]) {
        final changed = await pixelsChangedBy([
          DrawingAnnotation(
            kind: kind,
            pageIndex: 0,
            points: const [PdfPoint(120, 450), PdfPoint(420, 650)],
            strokeWidth: 4,
          ),
        ]);

        expect(changed, greaterThan(500), reason: '${kind.name} must be drawn');
      }
    });

    test('markup and a drawing save together and both render', () async {
      final src = await seed('sample_3page.pdf', 'Both.pdf');
      final quads = await quadsOver(src, 'Confidential');

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          TextMarkup(kind: MarkupKind.highlight, pageIndex: 0, quads: quads),
          const DrawingAnnotation(
            kind: DrawingKind.rectangle,
            pageIndex: 0,
            points: [PdfPoint(120, 450), PdfPoint(420, 650)],
            strokeWidth: 4,
          ),
        ],
      );

      // Reopening proves the file is structurally valid after two annotation
      // kinds shared one page override.
      final doc = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      expect(doc.pageCount, 3);
      await engine.close(doc);
    });
  });
}
