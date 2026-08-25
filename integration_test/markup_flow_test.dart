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
import 'package:folio/domain/annotations/quad_merge.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

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

      final out = await annotations.saveMarkup(
        sourceDocumentId: src.id,
        markups: [
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

        final out = await annotations.saveMarkup(
          sourceDocumentId: src.id,
          markups: [TextMarkup(kind: kind, pageIndex: 0, quads: quads)],
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

      await annotations.saveMarkup(
        sourceDocumentId: src.id,
        markups: [
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
      final out = await annotations.saveMarkup(
        sourceDocumentId: src.id,
        markups: [
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
      final out = await annotations.saveMarkup(
        sourceDocumentId: src.id,
        markups: [
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

      final once = await annotations.saveMarkup(
        sourceDocumentId: src.id,
        markups: [
          TextMarkup(kind: MarkupKind.highlight, pageIndex: 0, quads: quads),
        ],
      );
      final twice = await annotations.saveMarkup(
        sourceDocumentId: once.id,
        markups: [
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
        annotations.saveMarkup(
          sourceDocumentId: doc.id,
          markups: [
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
}
