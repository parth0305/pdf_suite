@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/fonts/font_assets.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/data/repositories/numbering_repository_impl.dart';
import 'package:folio/domain/editing/pdf_text_editor.dart';
import 'package:folio/domain/editing/text_edit.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/numbering/page_numbers.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../scripts/pdf_fixture_builder.dart';
import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late NumberingRepositoryImpl numbering;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('edit_flow');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    numbering = NumberingRepositoryImpl(
      library: library,
      documents: DocumentWriter(
        library: library,
        writer: SafeFileWriter(),
        libraryRoot: root,
      ),
      fonts: FontAssets(),
    );
    engine = PdfrxEngine();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// A document carrying text Folio wrote in a font Folio embedded: a
  /// composite font with its own widths and its own map back to characters.
  ///
  /// The most demanding case, and the one where a mistake in the encoding
  /// shows up as text that draws but cannot be read.
  Future<Uint8List> numbered(String name) async {
    final source = await library.importFile(
      await fixturePath('sample_3page.pdf'),
      displayName: name,
    );
    final out = await numbering.apply(
      source.id,
      // Numbers the fixture's own footer cannot produce, so finding them
      // proves they came from here.
      const PageNumbering(format: NumberFormat.ofTotal, startAt: 900),
    );

    return File(await library.resolveReadablePath(out)).readAsBytes();
  }

  Future<String> textOn(Uint8List pdf, int pageIndex) async {
    final file = File('${root.path}/probe_${pdf.length}.pdf');
    await file.writeAsBytes(pdf, flush: true);

    final handle = await engine.open(FileSource(file.path));
    final text = await engine.extractText(handle, pageIndex);
    await engine.close(handle);

    return text?.fullText ?? '';
  }

  Future<List<int>> render(Uint8List pdf, int pageIndex) async {
    final file = File('${root.path}/render_${pdf.length}.pdf');
    await file.writeAsBytes(pdf, flush: true);

    final handle = await engine.open(FileSource(file.path));
    final page = await engine.renderPage(
      handle,
      pageIndex,
      targetWidthPx: 400,
      targetHeightPx: 566,
    );
    await engine.close(handle);

    return page.bgraPixels;
  }

  int diff(List<int> a, List<int> b, {int fromRow = 0, int toRow = 566}) {
    var n = 0;
    for (var row = fromRow; row < toRow; row++) {
      for (var i = row * 400 * 4; i < (row + 1) * 400 * 4; i++) {
        if (a[i] != b[i]) n++;
      }
    }
    return n;
  }

  EditableRun numberRun(PdfTextEditor editor) => editor
      .runsOn(0)
      .firstWhere((r) => r.text != null && r.text!.contains('900'));

  group('editing text on a page', () {
    test('the text Folio wrote is found, and readable', () async {
      final editor = PdfTextEditor.parse(await numbered('Found.pdf'));

      expect(numberRun(editor).text, '900 of 902');
      expect(numberRun(editor).isEditable, isTrue);
    });

    // The failure this whole feature exists to avoid is a change that looks
    // right and reads wrong. Extraction is the only thing that can tell.
    test('the edited words are what the page now reads as', () async {
      final editor = PdfTextEditor.parse(await numbered('Reads.pdf'));
      final out = editor.apply(numberRun(editor), '200 of 900');

      final text = await textOn(out, 0);

      expect(text, contains('200 of 900'));
      expect(text, isNot(contains('900 of 902')));
    });

    test('the page still renders, and differently where it changed', () async {
      final before = await numbered('Renders.pdf');
      final editor = PdfTextEditor.parse(before);
      final after = editor.apply(numberRun(editor), '200 of 900');

      expect(
        diff(await render(before, 0), await render(after, 0)),
        greaterThan(20),
      );
    });

    // Everything above the footer is drawn by instructions this edit never
    // touched, and must come out byte for byte the same.
    test('the rest of the page is untouched', () async {
      final before = await numbered('Rest.pdf');
      final editor = PdfTextEditor.parse(before);
      final after = editor.apply(numberRun(editor), '200 of 900');

      expect(
        diff(await render(before, 0), await render(after, 0), toRow: 500),
        0,
      );
    });

    test("the document's other pages are untouched", () async {
      final before = await numbered('Pages.pdf');
      final editor = PdfTextEditor.parse(before);
      final after = editor.apply(numberRun(editor), '200 of 900');

      expect(diff(await render(before, 1), await render(after, 1)), 0);
      expect(await textOn(after, 2), contains('PLATYPUS-TOKEN-42'));
    });

    test('the document still opens and has all its pages', () async {
      final editor = PdfTextEditor.parse(await numbered('Opens.pdf'));
      final out = editor.apply(numberRun(editor), '200 of 900');

      final file = File('${root.path}/opens.pdf');
      await file.writeAsBytes(out, flush: true);

      final handle = await engine.open(FileSource(file.path));
      final pages = handle.pageCount;
      await engine.close(handle);

      expect(pages, 3);
    });

    // A shorter replacement is absorbed by an adjustment rather than by
    // moving anything.
    test('a shorter replacement reads back as itself', () async {
      final editor = PdfTextEditor.parse(await numbered('Shorter.pdf'));
      final out = editor.apply(numberRun(editor), '1');

      expect(await textOn(out, 0), contains('1'));
      expect(await textOn(out, 0), isNot(contains('900')));
    });

    test('an edit can be made twice over', () async {
      final first = PdfTextEditor.parse(await numbered('Twice.pdf'));
      final once = first.apply(numberRun(first), '200 of 900');

      final second = PdfTextEditor.parse(once);
      final run = second
          .runsOn(0)
          .firstWhere((r) => r.text != null && r.text!.contains('200'));
      final twice = second.apply(run, '990 of 022');

      expect(await textOn(twice, 0), contains('990 of 022'));
    });

    // The font Folio embeds carries only the glyphs it drew - across the
    // WHOLE document, not one page. Numbered 900 to 902, it has 0, 1, 2 and 9
    // but no 3, 4, 5 or 6, so editing to "123 of 456" is refused and the
    // characters are named.
    //
    // This is the practical shape of editing in a document's own font: the
    // characters already somewhere in it are the ones available.
    test(
      'a character the embedded subset lacks is refused, and named',
      () async {
        final editor = PdfTextEditor.parse(await numbered('Missing.pdf'));
        final plan = editor.plan(numberRun(editor), '123 of 456');

        expect(plan, isA<EditRefused>());
        expect((plan as EditRefused).reason, EditRefusal.missingCharacters);
        expect(plan.detail, containsAll(['3', '4', '5', '6']));
        // A 1 is there, because page two is numbered 901.
        expect(plan.detail, isNot(contains('1')));
      },
    );

    test('the rupee sign is refused by a font that never drew one', () async {
      final editor = PdfTextEditor.parse(await numbered('Rupee.pdf'));
      final plan = editor.plan(numberRun(editor), '900 of 902 ₹');

      expect((plan as EditRefused).detail, contains('₹'));
    });

    // The document's own Helvetica declares no widths, so nothing in it can
    // be fitted - and it is shown as fixed rather than accepting a tap and
    // then refusing whatever is typed.
    test('text in a font with no widths is not offered as editable', () async {
      final editor = PdfTextEditor.parse(await numbered('NoWidths.pdf'));
      final heading = editor
          .runsOn(0)
          .firstWhere((r) => r.text == 'Confidential Invoice');

      expect(heading.isEditable, isFalse);
    });

    // The whole reason for the adjustment: text that CONTINUES from the
    // edited run - a second show with no repositioning between them - must
    // not move. The page number has nothing after it on its line, so this
    // needs a document built for the purpose, and PDFium is what measures
    // where the characters actually landed.
    test('text continuing after the edit does not move', () async {
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>',
        '<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
            '/Resources << /Font << /F1 5 0 R >> >> >>',
        '<< /Length 52 >>\nstream\n'
            'BT /F1 12 Tf 72 700 Td (AAAA) Tj (ZZZZ) Tj ET\nendstream',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding /WinAnsiEncoding /FirstChar 32 /Widths '
            '[${List.filled(95, '500').join(' ')}] >>',
      ];
      final pdf = Uint8List.fromList(
        assemble(objects, '<< /Size 6 /Root 1 0 R >>'),
      );

      Future<double> zAt(Uint8List bytes, String name) async {
        final file = File('${root.path}/$name.pdf');
        await file.writeAsBytes(bytes, flush: true);

        final handle = await engine.open(FileSource(file.path));
        final text = await engine.extractText(handle, 0);
        await engine.close(handle);

        final at = text!.fullText.indexOf('Z');
        expect(at, greaterThanOrEqualTo(0), reason: text.fullText);

        return text.charRects[at].left;
      }

      final before = await zAt(pdf, 'before');

      final editor = PdfTextEditor.parse(pdf);
      final run = editor.runsOn(0).firstWhere((r) => r.text == 'AAAA');
      final after = await zAt(editor.apply(run, 'AA'), 'after');

      // Two glyphs narrower at 500 thousandths of 12 point is 12 points; the
      // adjustment gives that back, so the Zs stay where they were.
      expect(after, closeTo(before, 0.5));
    });

    test('the source document is untouched', () async {
      final source = await library.importFile(
        await fixturePath('sample_3page.pdf'),
        displayName: 'Source.pdf',
      );
      final bytes = await File(
        await library.resolveReadablePath(source),
      ).readAsBytes();

      final numberedDoc = await numbering.apply(
        source.id,
        const PageNumbering(format: NumberFormat.ofTotal, startAt: 900),
      );
      final editor = PdfTextEditor.parse(
        await File(
          await library.resolveReadablePath(numberedDoc),
        ).readAsBytes(),
      );
      editor.apply(numberRun(editor), '200 of 900');

      expect(
        await File(await library.resolveReadablePath(source)).readAsBytes(),
        bytes,
      );
    });
  });
}
