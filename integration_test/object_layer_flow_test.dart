@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('objlayer');
    engine = PdfrxEngine();
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<PdfDocumentHandle> open(List<int> bytes, String name) async {
    final f = File('${root.path}/$name.pdf')..writeAsBytesSync(bytes);
    return engine.open(FileSource(f.path));
  }

  Future<List<int>> renderBytes(List<int> bytes, String name) async {
    final h = await open(bytes, name);
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

  group('object layer', () {
    test('a rewritten document renders identically', () async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();

      final rebuilt = writePdfDocument(original, parsePdfObjects(original));

      final before = await renderBytes(original, 'before');
      final after = await renderBytes(rebuilt, 'after');

      expect(
        diff(before, after),
        0,
        reason: 'a rewrite must not change a single pixel',
      );
    });

    test('a rewritten document still reports its pages', () async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();
      final rebuilt = writePdfDocument(original, parsePdfObjects(original));

      final h = await open(rebuilt, 'pages');
      expect(h.pageCount, 3);
      await engine.close(h);
    });

    // A corrupted rewrite can still render a blank page. Text surviving is
    // the cheapest proof the content streams came through intact.
    test('text still extracts from a rewritten document', () async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();
      final rebuilt = writePdfDocument(original, parsePdfObjects(original));

      final h = await open(rebuilt, 'text');
      final text = await engine.extractText(h, 0);
      await engine.close(h);

      expect(text!.fullText, contains('Confidential'));
    });
  });
}
