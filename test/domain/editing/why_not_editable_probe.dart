import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/editing/pdf_font_resources.dart';
import 'package:folio/domain/editing/pdf_text_editor.dart';

/// Why each document is or is not editable, in the terms of the file itself
/// rather than in the terms of what Folio happened to return.
///
/// Kept because a corpus answers questions a fixture cannot. Every fixture in
/// this repository was written by one hand, and that hand put its arrays
/// inline - which is why a /Widths array in its own object went unnoticed
/// until a real document was tried.
///
///     flutter test test/domain/editing/why_not_editable_probe.dart \
///       --dart-define=dir=/some/folder
void main() {
  test('why not', () {
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

    final tally = <String, int>{};

    for (final file in files.take(60)) {
      final bytes = file.readAsBytesSync();
      final reason = _classify(bytes);

      tally[reason] = (tally[reason] ?? 0) + 1;

      if (reason != 'editable') {
        // ignore: avoid_print
        print(
          '${file.uri.pathSegments.last.padRight(52).substring(0, 52)}  '
          '$reason',
        );
      }
    }

    // ignore: avoid_print
    print('');
    final ordered = tally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in ordered) {
      // ignore: avoid_print
      print('${entry.value.toString().padLeft(3)}  ${entry.key}');
    }
  });
}

String _classify(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);

  List<EditableRun> runs;
  try {
    runs = PdfTextEditor.parse(bytes).runsOn(0);
  } on Object catch (e) {
    return 'threw ${e.runtimeType}';
  }

  if (runs.any((r) => r.isEditable)) return 'editable';

  final index = PdfObjectIndex.parse(text);
  final page = PdfObjectReader.parse(text).pageAt(0);

  if (page == null) {
    if (RegExp(r'/Type\s*/ObjStm').hasMatch(text)) {
      return 'no page: the page dictionary is inside a compressed object '
          'stream';
    }
    if (RegExp(r'/Encrypt').hasMatch(text)) {
      return 'no page: the document is encrypted';
    }
    return 'no page: not found by a plain scan, cause unknown';
  }

  if (runs.isEmpty) {
    final contents = RegExp(
      r'/Contents\s+(\d+)\s+\d+\s+R',
    ).firstMatch(page.rawDictionary);

    if (RegExp(r'/Encrypt').hasMatch(text)) {
      return 'no runs: the document is encrypted, so its streams are '
          'ciphertext';
    }
    if (contents == null) {
      return 'no runs: the page names no content stream Folio could follow';
    }

    final stream = streamContents(bytes, index, int.parse(contents.group(1)!));
    if (stream == null) {
      final body = index.bodyOf(int.parse(contents.group(1)!)) ?? '';
      final filter = RegExp(r'/Filter\s*/?(\w+)').firstMatch(body)?.group(1);
      return 'no runs: the content stream uses ${filter ?? 'a filter'} which '
          'Folio does not decode';
    }

    final source = latin1.decode(stream, allowInvalid: true);
    final showsText =
        source.contains('Tj') ||
        source.contains('TJ') ||
        source.contains("' ") ||
        source.contains('" ');
    final drawsImage = source.contains(' Do') || source.contains('BI ');

    if (!showsText && drawsImage) {
      return 'no text: the page is an image - a scan, needing OCR first';
    }
    if (!showsText) {
      return 'no text: the page draws nothing that shows text';
    }
    return 'no runs: the stream shows text that Folio did not find';
  }

  if (runs.every((r) => r.text == null)) {
    return 'unreadable: the fonts give no way to read their bytes back';
  }

  final standard = RegExp(
    r'/BaseFont\s*/(?:[A-Z]{6}\+)?'
    r'(Helvetica|Times|Courier|Arial|Symbol|ZapfDingbats)',
  ).hasMatch(text);

  if (standard) {
    return 'no widths: a standard font whose measurements the document does '
        'not carry';
  }

  // Say what the font actually is, so "unknown" never stands as an answer.
  final fonts = <String>{};
  for (final run in runs) {
    if (run.font == null || run.run.fontName == null) continue;
    if (run.font!.widths.isEmpty && run.font!.byCode == null) {
      fonts.add(run.run.fontName!);
    }
  }

  final subtypes = RegExp(r'/Subtype\s*/(\w+)')
      .allMatches(text)
      .map((m) => m.group(1)!)
      .where((s) => s.startsWith('Type') || s.startsWith('CIDFont'))
      .toSet();

  return 'no widths: fonts ${fonts.join(',')} of kind ${subtypes.join(',')}';
}
