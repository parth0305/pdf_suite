import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/editing/pdf_text_editor.dart';

/// Why documents whose text Folio can READ still cannot be edited.
///
///     flutter test test/domain/editing/font_widths_probe.dart \
///       --dart-define=dir=/some/folder
void main() {
  test('why widths are missing', () {
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

    var indirectWidths = 0;
    var standard14 = 0;
    var noWidthsAtAll = 0;
    var other = 0;

    for (final file in files.take(60)) {
      List<EditableRun> runs;
      try {
        runs = PdfTextEditor.parse(file.readAsBytesSync()).runsOn(0);
      } on Object {
        continue;
      }

      if (runs.isEmpty) continue;
      if (runs.any((r) => r.isEditable)) continue;
      if (runs.every((r) => r.text == null)) continue;

      // Look at the fonts this page actually names.
      final bytes = file.readAsBytesSync();
      final text = latin1.decode(bytes, allowInvalid: true);
      final index = PdfObjectIndex.parse(text);
      final page = PdfObjectReader.parse(text).pageAt(0);
      if (page == null) continue;

      final names = <String>{
        for (final run in runs)
          if (run.run.fontName != null) run.run.fontName!,
      };

      final reasons = <String>{};

      for (final match in RegExp(
        r'/([^\s/<>\[\]]+)\s+(\d+)\s+\d+\s+R',
      ).allMatches(_fontsDictionary(index, page.rawDictionary) ?? '')) {
        if (!names.contains(match.group(1))) continue;

        final font = index.bodyOf(int.parse(match.group(2)!)) ?? '';

        if (RegExp(r'/Widths\s+\d+\s+\d+\s+R').hasMatch(font)) {
          reasons.add('widths are an indirect reference');
        } else if (!font.contains('/Widths') &&
            RegExp(
              r'/BaseFont\s*/(Helvetica|Times|Courier|Symbol|ZapfDingbats)',
            ).hasMatch(font)) {
          reasons.add('a standard font with no widths');
        } else if (!font.contains('/Widths') && !font.contains('/W ')) {
          reasons.add('no widths at all');
        } else {
          reasons.add('widths present but unread');
        }
      }

      // ignore: avoid_print
      print(
        '${file.uri.pathSegments.last.padRight(48).substring(0, 48)}  '
        '${reasons.join(', ')}',
      );

      if (reasons.contains('widths are an indirect reference')) {
        indirectWidths++;
      } else if (reasons.contains('a standard font with no widths')) {
        standard14++;
      } else if (reasons.contains('no widths at all')) {
        noWidthsAtAll++;
      } else {
        other++;
      }
    }

    // ignore: avoid_print
    print(
      '\nindirect /Widths: $indirectWidths | standard 14 with no widths: '
      '$standard14 | no widths at all: $noWidthsAtAll | other: $other',
    );
  });
}

String? _fontsDictionary(PdfObjectIndex index, String page) {
  final resources = RegExp(r'/Resources\s+(\d+)\s+\d+\s+R').firstMatch(page);
  final dictionary = resources != null
      ? index.bodyOf(int.parse(resources.group(1)!)) ?? page
      : page;

  final fonts = RegExp(r'/Font\s+(\d+)\s+\d+\s+R').firstMatch(dictionary);
  if (fonts != null) return index.bodyOf(int.parse(fonts.group(1)!));

  final inline = RegExp(r'/Font\s*<<').firstMatch(dictionary);
  if (inline == null) return null;

  final close = PdfObjectIndex.matchingClose(dictionary, inline.end - 2);
  return close < 0 ? null : dictionary.substring(inline.end - 2, close + 2);
}
