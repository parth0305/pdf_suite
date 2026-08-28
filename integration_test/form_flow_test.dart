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
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/flatten_repository_impl.dart';
import 'package:folio/data/repositories/form_repository_impl.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/forms/form_field.dart';
import 'package:folio/domain/forms/pdf_form_reader.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late FormRepositoryImpl subject;
  late FlattenRepositoryImpl flatten;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('form_flow');
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
    subject = FormRepositoryImpl(library: library, documents: writer);
    flatten = FlattenRepositoryImpl(library: library, documents: writer);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<LibraryDocument> seed(String name) async => library.importFile(
    await fixturePath('membership_form.pdf'),
    displayName: name,
  );

  /// The page rendered with appearance streams drawn but form handling OFF.
  ///
  /// This is the render that can tell whether Folio generated an appearance.
  /// With full form rendering, the reader draws the value itself and an
  /// untouched document looks filled too; with annotations off entirely,
  /// nothing shows either way.
  Future<Uint8List> renderAppearances(
    LibraryDocument d, {
    PdfAnnotationRenderingMode mode = PdfAnnotationRenderingMode.none,
  }) async {
    final doc = await PdfDocument.openFile(
      await library.resolveReadablePath(d),
    );
    try {
      final image = await doc.pages[0].render(
        fullWidth: 595,
        fullHeight: 842,
        annotationRenderingMode: mode,
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

  int diff(List<int> a, List<int> b) {
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) n++;
    }
    return n;
  }

  Future<FormField> field(LibraryDocument d, String name) async =>
      (await subject.fields(d.id)).firstWhere((f) => f.name == name);

  group('form filling', () {
    test('the fields of a real form are read off the device', () async {
      final src = await seed('Read.pdf');
      final fields = await subject.fields(src.id);

      expect(fields.map((f) => f.name), contains('full name'));
      expect((await field(src, 'plan')).widgets.length, 2);
    });

    test('a filled value is stored and read back', () async {
      final src = await seed('Fill.pdf');
      final out = await subject.fill(src.id, {'full name': 'Priya Menon'});

      expect((await field(out, 'full name')).value, 'Priya Menon');
    });

    // The point of generating appearances: the value is visible even in a
    // reader that draws no form fields of its own.
    // The one render that can prove Folio GENERATED an appearance. PDFium
    // draws no widget appearance in either annotation mode, so a filled
    // document and an untouched one look identical until the appearance is
    // painted into the page - and flattening only has something to paint if
    // there was an appearance to paint.
    test('the generated appearance is what flattening paints', () async {
      final src = await seed('Where.pdf');
      const off = PdfAnnotationRenderingMode.none;
      final before = await renderAppearances(src, mode: off);

      final filled = await subject.fill(src.id, {'full name': 'Priya Menon'});
      expect(
        diff(before, await renderAppearances(filled, mode: off)),
        0,
        reason: 'a filled field is still an annotation',
      );

      final flat = await flatten.apply(filled.id);
      expect(
        diff(before, await renderAppearances(flat, mode: off)),
        greaterThan(100),
      );
    });

    test('the filled text is extractable, so it is real text', () async {
      final src = await seed('Extract.pdf');
      final out = await subject.fill(src.id, {'full name': 'Priya Menon'});

      // Text extraction reads page content, and a field's value is not page
      // content until it is flattened.
      final flat = await flatten.apply(out.id);
      final opened = await PdfDocument.openFile(
        await library.resolveReadablePath(flat),
      );
      final text = await opened.pages[0].loadText();
      await opened.dispose();

      expect(text!.fullText, contains('Priya Menon'));
    });

    test('a ticked checkbox reads back as ticked', () async {
      final src = await seed('Tick.pdf');
      final out = await subject.fill(src.id, {'newsletter': 'On'});

      expect((await field(out, 'newsletter')).value, 'On');
    });

    test('a radio choice reads back off the group', () async {
      final src = await seed('Radio.pdf');
      final out = await subject.fill(src.id, {'plan': 'Premium'});

      expect((await field(out, 'plan')).value, 'Premium');
    });

    test('a filled form still flattens', () async {
      final src = await seed('Flat.pdf');
      final filled = await subject.fill(src.id, {'full name': 'Priya'});

      final flat = await flatten.apply(filled.id);
      final text = latin1.decode(
        await File(await library.resolveReadablePath(flat)).readAsBytes(),
        allowInvalid: true,
      );

      // The filled field is page content now. 'issued on' is not: it holds a
      // value with no appearance to paint, so flattening keeps it rather than
      // deleting what it holds - and the document stays a form for its sake.
      final after = PdfFormReader.parse(text).fields.map((f) => f.name);

      expect(after, isNot(contains('full name')));
      expect(after, contains('issued on'));
    });

    test('the source document is untouched', () async {
      final src = await seed('Source.pdf');
      final bytes = await File(
        await library.resolveReadablePath(src),
      ).readAsBytes();

      await subject.fill(src.id, {'full name': 'Priya'});

      expect(
        await File(await library.resolveReadablePath(src)).readAsBytes(),
        bytes,
      );
    });
  });
}
