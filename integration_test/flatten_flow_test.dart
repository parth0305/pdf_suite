@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/flatten_repository_impl.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/library_document.dart';
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
  late FlattenRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flatten_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    final writer = DocumentWriter(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    annotations = AnnotationRepositoryImpl(library: library, documents: writer);
    subject = FlattenRepositoryImpl(library: library, documents: writer);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// The page as it renders with annotations switched OFF.
  ///
  /// This is the whole point of the feature. With annotations on, a flattened
  /// document and an annotated one look identical, so a render that leaves
  /// them on cannot tell flattening from doing nothing at all.
  Future<Uint8List> renderWithout(LibraryDocument d) async {
    final doc = await PdfDocument.openFile(
      await library.resolveReadablePath(d),
    );
    try {
      final image = await doc.pages[0].render(
        fullWidth: 400,
        fullHeight: 566,
        annotationRenderingMode: PdfAnnotationRenderingMode.none,
      );
      try {
        return Uint8List.fromList(image!.pixels);
      } finally {
        image!.dispose();
      }
    } finally {
      await doc.dispose();
    }
  }

  Future<Uint8List> renderWith(LibraryDocument d) async {
    final doc = await PdfDocument.openFile(
      await library.resolveReadablePath(d),
    );
    try {
      final image = await doc.pages[0].render(fullWidth: 400, fullHeight: 566);
      try {
        return Uint8List.fromList(image!.pixels);
      } finally {
        image!.dispose();
      }
    } finally {
      await doc.dispose();
    }
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

  Future<LibraryDocument> stamped(String name) async {
    final src = await seed(name);
    return annotations.saveAnnotations(
      sourceDocumentId: src.id,
      annotations: [
        const Stamp(
          preset: StampPreset.approved,
          pageIndex: 0,
          anchorPt: PdfPoint(120, 600),
        ),
      ],
    );
  }

  group('flattening', () {
    test('the mark is still drawn with annotations switched off', () async {
      final src = await stamped('Flat.pdf');
      final plain = await seed('Plain.pdf');

      // The premise: with annotations off, the stamp is invisible. Without
      // this, the test below cannot tell a flattened stamp from a rendering
      // mode that was never honoured.
      expect(
        diff(await renderWithout(src), await renderWithout(plain)),
        0,
        reason: 'an annotation is not page content until it is flattened',
      );

      final out = await subject.apply(src.id);

      expect(
        diff(await renderWithout(out), await renderWithout(plain)),
        greaterThan(500),
      );
    });

    test('the page looks the same as it did before', () async {
      final src = await stamped('Same.pdf');
      final before = await renderWith(src);

      final out = await subject.apply(src.id);

      // Not zero: the appearance is placed by a matrix rather than drawn by
      // the annotation layer, and the two round pixels differently.
      expect(diff(before, await renderWith(out)), lessThan(2000));
    });

    // The claim flattening makes is that the mark can no longer be selected,
    // moved or deleted. That is decided by the annotation list, not by the
    // pixels - two draws of the same stamp in the same place look identical.
    test('the mark is no longer an annotation anyone can grab', () async {
      final src = await stamped('Grab.pdf');
      final before = PdfAnnotationReader.parse(
        latin1.decode(
          await File(await library.resolveReadablePath(src)).readAsBytes(),
          allowInvalid: true,
        ),
      );
      expect(before.onPage(0), isNotEmpty, reason: 'premise: there is one');

      final out = await subject.apply(src.id);
      final after = PdfAnnotationReader.parse(
        latin1.decode(
          await File(await library.resolveReadablePath(out)).readAsBytes(),
          allowInvalid: true,
        ),
      );

      expect(after.onPage(0), isEmpty);
    });

    test('the source document is untouched', () async {
      final src = await stamped('Source.pdf');
      final bytes = await File(
        await library.resolveReadablePath(src),
      ).readAsBytes();

      await subject.apply(src.id);

      expect(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
        bytes,
      );
    });

    test('a document with no annotations is refused', () async {
      final src = await seed('Nothing.pdf');

      expect(subject.apply(src.id), throwsA(isA<Exception>()));
    });
  });
}
