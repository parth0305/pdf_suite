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
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/quad_merge.dart';
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
  late AnnotationRepositoryImpl annotations;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('drawing_flow');
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

  Future<List<int>> renderPage0(LibraryDocument d) async {
    final handle = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final px = (await engine.renderPage(
      handle,
      0,
      targetWidthPx: 400,
      targetHeightPx: 566,
    )).bgraPixels;
    await engine.close(handle);
    return px;
  }

  /// Renders before and after, and returns how many bytes differ. The gate on
  /// this whole slice: a drawing must RENDER through the production path, not
  /// merely be present in the file.
  Future<int> pixelsChangedBy(String fixture, List<Annotation> drawings) async {
    final src = await seed(
      fixture,
      'D-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    final before = await renderPage0(src);

    final out = await annotations.saveAnnotations(
      sourceDocumentId: src.id,
      annotations: drawings,
    );
    final after = await renderPage0(out);

    var changed = 0;
    for (var i = 0; i < before.length; i++) {
      if (before[i] != after[i]) changed++;
    }
    return changed;
  }

  DrawingAnnotation shape(DrawingKind kind) => DrawingAnnotation(
    kind: kind,
    pageIndex: 0,
    strokes: [
      const [PdfPoint(120, 450), PdfPoint(420, 650)],
    ],
    strokeWidth: 4,
  );

  const inkStroke = DrawingAnnotation(
    kind: DrawingKind.ink,
    pageIndex: 0,
    strokes: [
      [
        PdfPoint(100, 500),
        PdfPoint(200, 600),
        PdfPoint(300, 500),
        PdfPoint(400, 600),
      ],
    ],
    strokeWidth: 4,
  );

  group('drawing flow', () {
    test('an ink stroke renders when the document is reopened', () async {
      expect(
        await pixelsChangedBy('sample_3page.pdf', [inkStroke]),
        greaterThan(500),
        reason: 'the ink must actually be drawn',
      );
    });

    test('every shape kind renders', () async {
      for (final kind in [
        DrawingKind.rectangle,
        DrawingKind.ellipse,
        DrawingKind.line,
        DrawingKind.arrow,
      ]) {
        expect(
          await pixelsChangedBy('sample_3page.pdf', [shape(kind)]),
          greaterThan(500),
          reason: '${kind.name} must be drawn',
        );
      }
    });

    // The case that was impossible before this slice: markup needs a text
    // layer to attach to, drawing needs nothing but the page.
    test('drawing renders on a scanned page with no text layer', () async {
      expect(
        await pixelsChangedBy('scanned_no_text.pdf', [inkStroke]),
        greaterThan(500),
        reason: 'drawing must not depend on extractable text',
      );
    });

    test('the source document is byte-identical afterwards', () async {
      final src = await seed('sample_3page.pdf', 'Untouched.pdf');
      final before = await hashOf(src);

      await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [inkStroke],
      );

      expect(await hashOf(src), before);
    });

    test('extracted text is unchanged by drawing', () async {
      final src = await seed('sample_3page.pdf', 'TextIntact.pdf');
      final srcHandle = await engine.open(
        FileSource(await library.resolveReadablePath(src)),
      );
      final before = (await engine.extractText(srcHandle, 0))!.fullText;
      await engine.close(srcHandle);

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [inkStroke],
      );

      final outHandle = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      final after = (await engine.extractText(outHandle, 0))!.fullText;
      await engine.close(outHandle);

      expect(after, before);
    });

    // The point of the sealed type: one session, one save, one document.
    test('a highlight and a drawing save together into one document', () async {
      final src = await seed('sample_3page.pdf', 'Both.pdf');

      final handle = await engine.open(
        FileSource(await library.resolveReadablePath(src)),
      );
      final text = await engine.extractText(handle, 0);
      final index = text!.fullText.indexOf('Confidential');
      final quads = mergeIntoLineQuads(
        text.charRects.sublist(index, index + 'Confidential'.length),
      );
      await engine.close(handle);

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          TextMarkup(kind: MarkupKind.highlight, pageIndex: 0, quads: quads),
          inkStroke,
        ],
      );

      final bytes = await File(
        await library.resolveReadablePath(out),
      ).readAsBytes();
      final raw = String.fromCharCodes(bytes);
      expect(raw, contains('/Subtype /Highlight'));
      expect(raw, contains('/Subtype /Ink'));

      // Structurally valid after two annotation kinds shared one page override.
      final reopened = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      expect(reopened.pageCount, 3);
      await engine.close(reopened);
    });

    test('metadata survives the drawing save', () async {
      final src = await seed('with_metadata.pdf', 'Meta.pdf');
      final before = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
      )!;

      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [inkStroke],
      );

      final after = PdfMetadata.readFrom(
        await File(await library.resolveReadablePath(out)).readAsBytes(),
      )!;
      expect(after.title, before.title);
      expect(after.author, before.author);
    });

    test('a cross-reference-stream document is refused, not mangled', () async {
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
          annotations: [inkStroke],
        ),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });
  });
}
