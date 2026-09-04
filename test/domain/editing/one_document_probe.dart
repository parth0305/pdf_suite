import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/pdf_text_editor.dart';

/// Everything about one document's runs, page by page.
///
///     flutter test test/domain/editing/one_document_probe.dart \
///       --dart-define=file=/path/to.pdf
void main() {
  test('one document', () {
    const path = String.fromEnvironment('file');
    if (path.isEmpty) {
      markTestSkipped('pass --dart-define=file=<pdf>');
      return;
    }

    final editor = PdfTextEditor.parse(File(path).readAsBytesSync());

    for (var page = 0; page < 6; page++) {
      final runs = editor.runsOn(page);
      if (runs.isEmpty) {
        // ignore: avoid_print
        print('page $page: no runs');
        continue;
      }

      final editable = runs.where((r) => r.isEditable).toList();
      // ignore: avoid_print
      print(
        'page $page: ${runs.length} runs, ${editable.length} editable, '
        'fonts ${runs.map((r) => r.run.fontName).toSet().join(',')}',
      );

      for (final run in editable.take(6)) {
        // ignore: avoid_print
        print(
          '   "${(run.text ?? '').padRight(28).substring(0, 28)}" '
          'x=${run.x.toStringAsFixed(1)} y=${run.y.toStringAsFixed(1)} '
          'size=${run.run.fontSize} '
          'scale=${run.run.transform.verticalScale.toStringAsFixed(1)} '
          'room=${run.availableWidth?.toStringAsFixed(1)}',
        );
      }
    }
  });
}
