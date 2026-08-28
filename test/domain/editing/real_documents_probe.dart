import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/editing/pdf_text_editor.dart';

/// Runs the editor over real documents and reports what it makes of them.
///
/// Not part of the suite: point it at a directory when the question is why a
/// particular file behaves as it does.
///
///     flutter test test/domain/editing/real_documents_probe.dart \
///       --dart-define=dir=/some/folder
void main() {
  test('what the editor makes of real documents', () {
    const dir = String.fromEnvironment('dir');
    if (dir.isEmpty) {
      markTestSkipped('pass --dart-define=dir=<folder>');
      return;
    }

    final files =
        Directory(dir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pdf'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    var noPages = 0;
    var noRuns = 0;
    var noneReadable = 0;
    var noneEditable = 0;
    var editable = 0;

    for (final file in files.take(60)) {
      final name = file.uri.pathSegments.last;
      String verdict;

      try {
        final editor = PdfTextEditor.parse(file.readAsBytesSync());
        final runs = editor.runsOn(0);

        if (runs.isEmpty) {
          // Distinguishes "the page has no text" from "no page was found at
          // all", which are very different problems wearing the same message.
          final anyPage = editor.runsOn(0).isEmpty && _hasPages(file);
          verdict = anyPage ? 'PAGE FOUND, no runs' : 'NO PAGES FOUND';
          if (anyPage) {
            noRuns++;
          } else {
            noPages++;
          }
        } else {
          final readable = runs.where((r) => r.text != null).length;
          final canEdit = runs.where((r) => r.isEditable).length;

          if (readable == 0) {
            noneReadable++;
            verdict = '${runs.length} runs, NONE readable';
          } else if (canEdit == 0) {
            noneEditable++;
            verdict = '${runs.length} runs, $readable readable, NONE editable';
          } else {
            editable++;
            verdict = '${runs.length} runs, $canEdit editable';
          }
        }
      } on Object catch (e) {
        verdict = 'THREW ${e.runtimeType}';
      }

      // ignore: avoid_print
      print('${name.padRight(56).substring(0, 56)}  $verdict');
    }

    // ignore: avoid_print
    print(
      '\nno pages found: $noPages | page but no runs: $noRuns | '
      'none readable: $noneReadable | none editable: $noneEditable | '
      'editable: $editable',
    );
  });
}

bool _hasPages(File file) {
  final text = String.fromCharCodes(file.readAsBytesSync().take(400000));
  return text.contains('/Type /Page') || text.contains('/Type/Page');
}
