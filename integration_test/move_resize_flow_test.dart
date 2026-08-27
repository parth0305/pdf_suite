@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:convert';

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
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/ink_reshape.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
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
    root = await Directory.systemTemp.createTemp('move_flow');
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

  const width = 400;
  const height = 566;

  Future<List<int>> render(LibraryDocument d) async {
    final h = await engine.open(
      FileSource(await library.resolveReadablePath(d)),
    );
    final px = (await engine.renderPage(
      h,
      0,
      targetWidthPx: width,
      targetHeightPx: height,
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

  /// How many pixels differ within a column band, so we can ask whether an
  /// annotation is still where it used to be.
  int diffInColumns(List<int> a, List<int> b, int fromX, int toX) {
    var n = 0;
    for (var x = fromX; x <= toX; x++) {
      for (var y = 0; y < height; y++) {
        final i = (y * width + x) * 4;
        if (a[i] != b[i]) n++;
      }
    }
    return n;
  }

  Future<LibraryDocument> seed(String name) async => library.importFile(
    await fixturePath('sample_3page.pdf'),
    displayName: name,
  );

  /// A filled-ish rectangle at the left of the page.
  Future<LibraryDocument> withBox(LibraryDocument src) =>
      annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: const [
          DrawingAnnotation(
            kind: DrawingKind.rectangle,
            pageIndex: 0,
            strokes: [
              [PdfPoint(60, 600), PdfPoint(180, 700)],
            ],
            strokeWidth: 6,
          ),
        ],
      );

  const target = TextRect(left: 380, bottom: 600, right: 500, top: 700);

  group('move and resize flow', () {
    test('a moved annotation draws in its new position', () async {
      final src = await seed('Move.pdf');
      final out = await withBox(src);
      final before = await render(out);

      final a = (await edits.load(out.id)).single;
      final moved = await edits.save(
        documentId: out.id,
        deleted: const {},
        restyled: const {},
        moved: {a.objectNumber: target},
      );

      expect(diff(before, await render(moved)), greaterThan(200));
    });

    test('it no longer draws in its old position', () async {
      final src = await seed('Vacated.pdf');
      final plain = await render(src);
      final out = await withBox(src);

      final a = (await edits.load(out.id)).single;
      final moved = await edits.save(
        documentId: out.id,
        deleted: const {},
        restyled: const {},
        moved: {a.objectNumber: target},
      );
      final after = await render(moved);

      // Columns the box originally covered: PDF x 60..180 of a 595pt page.
      final fromX = (60 / 595 * width).round();
      final toX = (180 / 595 * width).round();

      expect(
        diffInColumns(plain, after, fromX, toX),
        lessThan(200),
        reason: 'the old position should be back to bare page',
      );
    });

    // Geometry must follow /Rect. Note what this does NOT assert: PDFium maps
    // an appearance /BBox onto /Rect, so a stale /InkList still RENDERS in the
    // right place. Rendering cannot see this bug at all - only reading the
    // geometry back can. Verified by mutation: deleting the geometry rewrite
    // leaves every render assertion green and fails only this one.
    test('geometry follows the annotation when it moves', () async {
      final src = await seed('Geometry.pdf');
      // INK, not a rectangle: a /Square's geometry IS its /Rect, so there is
      // no separate geometry key for a stale-geometry bug to live in.
      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: const [
          DrawingAnnotation(
            kind: DrawingKind.ink,
            pageIndex: 0,
            strokes: [
              [PdfPoint(60, 600), PdfPoint(120, 700), PdfPoint(180, 600)],
            ],
            strokeWidth: 6,
          ),
        ],
      );

      final a = (await edits.load(out.id)).single;
      final moved = await edits.save(
        documentId: out.id,
        deleted: const {},
        restyled: const {},
        moved: {a.objectNumber: target},
      );

      final after = (await edits.load(moved.id)).single;
      expect(after.rectPt.left, closeTo(target.left, 1));

      final strokes = (after.reconstructed! as DrawingAnnotation).strokes;
      final xs = strokes.expand((s) => s).map((p) => p.x);
      expect(
        xs.reduce((a, b) => a < b ? a : b),
        closeTo(target.left, 1),
        reason: 'the geometry must move with the rect, not stay behind',
      );
    });

    // A restyle regenerates the appearance from geometry. With consistent
    // geometry it lands where the annotation now is.
    test('restyling after a move keeps the new position', () async {
      final src = await seed('Restyled.pdf');
      final plain = await render(src);
      final out = await withBox(src);

      final a = (await edits.load(out.id)).single;
      final moved = await edits.save(
        documentId: out.id,
        deleted: const {},
        restyled: const {},
        moved: {a.objectNumber: target},
      );

      final afterMove = (await edits.load(moved.id)).single;
      final restyled = await edits.save(
        documentId: moved.id,
        deleted: const {},
        restyled: {
          afterMove.objectNumber: const AnnotationStyle(
            colorArgb: 0xFF1976D2,
            strokeWidth: 4,
          ),
        },
        moved: const {},
      );
      final after = await render(restyled);

      final newFrom = (380 / 595 * width).round();
      final newTo = (500 / 595 * width).round();
      expect(
        diffInColumns(plain, after, newFrom, newTo),
        greaterThan(200),
        reason: 'it must still be drawn where it was moved to',
      );
    });

    test('a stamp moves even though it cannot be restyled', () async {
      final src = await seed('Stamp.pdf');
      final out = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: const [
          Stamp(
            preset: StampPreset.approved,
            pageIndex: 0,
            anchorPt: PdfPoint(60, 700),
          ),
        ],
      );
      final before = await render(out);

      final a = (await edits.load(out.id)).single;
      expect(a.restylable, isFalse);
      expect(a.movable, isTrue);

      final moved = await edits.save(
        documentId: out.id,
        deleted: const {},
        restyled: const {},
        moved: {
          a.objectNumber: const TextRect(
            left: 300,
            bottom: 600,
            right: 460,
            top: 640,
          ),
        },
      );

      expect(diff(before, await render(moved)), greaterThan(200));
    });

    test('a resized shape covers more of the page', () async {
      final src = await seed('Resize.pdf');
      final plain = await render(src);
      final out = await withBox(src);
      final small = diff(plain, await render(out));

      final a = (await edits.load(out.id)).single;
      final bigger = await edits.save(
        documentId: out.id,
        deleted: const {},
        restyled: const {},
        moved: {
          a.objectNumber: const TextRect(
            left: 60,
            bottom: 400,
            right: 400,
            top: 700,
          ),
        },
      );

      expect(diff(plain, await render(bigger)), greaterThan(small));
    });

    test('the source document is byte-identical afterwards', () async {
      final src = await seed('Untouched.pdf');
      final path = await library.resolveReadablePath(src);
      final before = sha256.convert(await File(path).readAsBytes()).toString();

      final out = await withBox(src);
      final a = (await edits.load(out.id)).single;
      await edits.save(
        documentId: out.id,
        deleted: const {},
        restyled: const {},
        moved: {a.objectNumber: target},
      );

      expect(sha256.convert(await File(path).readAsBytes()).toString(), before);
    });
  });

  // Moving and resizing change the whole annotation. Reshaping moves ONE
  // point, which is the thing SP-3f could not do.
  group('reshaping one ink point', () {
    test('the stroke changes shape and the page still renders', () async {
      final src = await seed('Reshape.pdf');

      final drawn = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          const DrawingAnnotation(
            kind: DrawingKind.ink,
            pageIndex: 0,
            strokes: [
              [PdfPoint(100, 400), PdfPoint(200, 400), PdfPoint(300, 400)],
            ],
            colorArgb: 0xFF000000,
            strokeWidth: 4,
          ),
        ],
      );
      final before = await render(drawn);

      final ink = PdfAnnotationReader.parse(
        latin1.decode(
          await File(await library.resolveReadablePath(drawn)).readAsBytes(),
          allowInvalid: true,
        ),
      ).onPage(0).firstWhere((a) => a.subtype == 'Ink');
      final reshape = reshapeInk(
        ink.reconstructed! as DrawingAnnotation,
        const InkPointRef(stroke: 0, point: 1),
        // Pull the middle point well above the line.
        const PdfPoint(200, 600),
      )!;

      final out = await edits.save(
        documentId: drawn.id,
        deleted: const {},
        restyled: const {},
        moved: const {},
        reshaped: {ink.objectNumber: reshape},
      );

      expect(diff(before, await render(out)), greaterThan(200));
    });

    // The /Rect must follow the points. One left where it was clips the
    // appearance, so the reshaped stroke is drawn and then cut off - and the
    // pixels above the old rectangle would stay empty.
    test('the rectangle grows so the new shape is not clipped', () async {
      final src = await seed('Clip.pdf');

      final drawn = await annotations.saveAnnotations(
        sourceDocumentId: src.id,
        annotations: [
          const DrawingAnnotation(
            kind: DrawingKind.ink,
            pageIndex: 0,
            strokes: [
              [PdfPoint(100, 400), PdfPoint(200, 400), PdfPoint(300, 400)],
            ],
            colorArgb: 0xFF000000,
            strokeWidth: 4,
          ),
        ],
      );

      final ink = PdfAnnotationReader.parse(
        latin1.decode(
          await File(await library.resolveReadablePath(drawn)).readAsBytes(),
          allowInvalid: true,
        ),
      ).onPage(0).firstWhere((a) => a.subtype == 'Ink');
      final reshape = reshapeInk(
        ink.reconstructed! as DrawingAnnotation,
        const InkPointRef(stroke: 0, point: 1),
        const PdfPoint(200, 620),
      )!;

      final out = await edits.save(
        documentId: drawn.id,
        deleted: const {},
        restyled: const {},
        moved: const {},
        reshaped: {ink.objectNumber: reshape},
      );

      // The moved point is at y=620pt on an 842pt page: render row
      // (842-620)/842*566 = 149. Well above the original stroke at row 297.
      final pixels = await render(out);
      var darkNearTheTop = 0;
      for (var y = 130; y < 175; y++) {
        for (var x = 120; x < 280; x++) {
          if (pixels[(y * 400 + x) * 4] < 128) darkNearTheTop++;
        }
      }

      expect(
        darkNearTheTop,
        greaterThan(10),
        reason: 'the new peak is drawn, not clipped away by a stale /Rect',
      );
    });
  });
}
