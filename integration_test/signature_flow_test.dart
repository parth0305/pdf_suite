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
import 'package:folio/data/local/signature_dao.dart';
import 'package:folio/data/repositories/annotation_edit_repository_impl.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/signature_repository_impl.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/domain/signatures/signature_geometry.dart';
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
  late SignatureRepositoryImpl signatures;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('signature_flow');
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
    signatures = SignatureRepositoryImpl(dao: SignatureDao(db));
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

  /// Two strokes at opposite ends of the unit box, with a clear gap between.
  Future<SavedSignature> twoStroke() => signatures.add(
    label: 'Full',
    strokes: const [
      [PdfPoint(0, 0), PdfPoint(0.15, 1), PdfPoint(0.35, 0.5)],
      [PdfPoint(0.65, 0.5), PdfPoint(0.85, 1), PdfPoint(1, 0)],
    ],
    aspectRatio: 3,
  );

  Future<LibraryDocument> signed(
    LibraryDocument src,
    SavedSignature sig,
    TextRect box,
  ) => annotations.saveAnnotations(
    sourceDocumentId: src.id,
    annotations: [
      DrawingAnnotation(
        kind: DrawingKind.ink,
        pageIndex: 0,
        strokes: placeSignature(sig, box: box),
        strokeWidth: 4,
      ),
    ],
  );

  group('signature flow', () {
    test('a placed signature renders', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Sign.pdf',
      );
      final before = await render(src);

      final out = await signed(
        src,
        await twoStroke(),
        const TextRect(left: 100, bottom: 400, right: 460, top: 520),
      );

      expect(diff(before, await render(out)), greaterThan(500));
    });

    // THE assertion that catches joining. The two strokes end and start at
    // mid-height, so a line joining them crosses open space rather than
    // hugging the /BBox edge where clipping would hide most of it.
    //
    // Measured on device: 68 of the 74 columns in the gap stay untouched when
    // the strokes are separate, and 0 stay untouched when they are joined.
    test('a two-stroke signature leaves a gap between its strokes', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Gap.pdf',
      );
      final before = await render(src);

      const box = TextRect(left: 100, bottom: 400, right: 460, top: 520);
      final out = await signed(src, await twoStroke(), box);
      final after = await render(out);

      final page = await engine.open(
        FileSource(await library.resolveReadablePath(src)),
      );
      final info = await engine.pageInfo(page, 0);
      await engine.close(page);

      // The gap spans 0.35..0.65 of the signature's width.
      int columnOf(double fraction) =>
          ((box.left + (box.right - box.left) * fraction) /
                  info.widthPt *
                  width)
              .round();

      var untouched = 0;
      for (var x = columnOf(0.35); x <= columnOf(0.65); x++) {
        var changed = false;
        for (var y = 0; y < height && !changed; y++) {
          final i = (y * width + x) * 4;
          if (before[i] != after[i]) changed = true;
        }
        if (!changed) untouched++;
      }

      expect(
        untouched,
        greaterThan(60),
        reason: 'the gap between two strokes must stay empty',
      );
    });

    test('a placed signature is ONE annotation with two strokes', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'One.pdf',
      );
      final out = await signed(
        src,
        await twoStroke(),
        const TextRect(left: 100, bottom: 400, right: 460, top: 520),
      );

      final loaded = await edits.load(out.id);
      expect(loaded, hasLength(1));
      expect(loaded.single.subtype, 'Ink');
      expect(
        (loaded.single.reconstructed! as DrawingAnnotation).strokes,
        hasLength(2),
      );
    });

    test('deleting removes the whole signature, not one stroke', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Remove.pdf',
      );
      final plain = await render(src);
      final out = await signed(
        src,
        await twoStroke(),
        const TextRect(left: 100, bottom: 400, right: 460, top: 520),
      );

      final target = (await edits.load(out.id)).single;
      final cleaned = await edits.save(
        documentId: out.id,
        deleted: {target.objectNumber},
        restyled: const {},
        moved: const {},
      );

      expect(
        diff(plain, await render(cleaned)),
        lessThan(500),
        reason: 'the page should be back to how it started',
      );
    });

    test('the source document is byte-identical afterwards', () async {
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Untouched.pdf',
      );
      final path = await library.resolveReadablePath(src);
      final before = sha256.convert(await File(path).readAsBytes()).toString();

      await signed(
        src,
        await twoStroke(),
        const TextRect(left: 100, bottom: 400, right: 460, top: 520),
      );

      expect(sha256.convert(await File(path).readAsBytes()).toString(), before);
    });

    // A stretched signature looks forged.
    test('a tall box and a wide box give the same aspect ratio', () async {
      final sig = await twoStroke();
      final src = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Aspect.pdf',
      );

      double aspectOf(TextRect box) {
        final strokes = placeSignature(sig, box: box);
        final flat = strokes.expand((s) => s).toList();
        final left = flat.map((p) => p.x).reduce((a, b) => a < b ? a : b);
        final right = flat.map((p) => p.x).reduce((a, b) => a > b ? a : b);
        final bottom = flat.map((p) => p.y).reduce((a, b) => a < b ? a : b);
        final top = flat.map((p) => p.y).reduce((a, b) => a > b ? a : b);
        return (right - left) / (top - bottom);
      }

      final tall = aspectOf(
        const TextRect(left: 100, bottom: 300, right: 300, top: 600),
      );
      final wide = aspectOf(
        const TextRect(left: 100, bottom: 300, right: 500, top: 380),
      );

      expect(tall, closeTo(wide, 0.01));

      // And the document still opens after signing with each.
      final out = await signed(
        src,
        sig,
        const TextRect(left: 100, bottom: 300, right: 500, top: 380),
      );
      final handle = await engine.open(
        FileSource(await library.resolveReadablePath(out)),
      );
      expect(handle.pageCount, 3);
      await engine.close(handle);
    });
  });
}
