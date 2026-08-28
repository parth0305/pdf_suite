import 'package:folio/domain/editing/font_encoding.dart';
import 'package:folio/domain/editing/text_run_finder.dart';

/// Why an edit cannot be made.
///
/// Refusing is a feature. A document that LOOKS edited and is subtly wrong -
/// a character the font cannot draw, text overlapping what follows it - is
/// worse than one that says no.
enum EditRefusal {
  /// The run's bytes cannot be read, so there is nothing to change.
  unreadable,

  /// The font has no way to write some of the replacement.
  missingCharacters,

  /// The widths of the font's glyphs are not known, so the replacement
  /// cannot be fitted without moving everything after it.
  unknownWidths,

  /// The replacement is wider than the space before whatever comes next.
  wouldOverlap,

  /// Invisible text - what OCR puts under a scan. Editing it changes nothing
  /// anybody can see, which is not what the person asking expected.
  notVisible,
}

/// The outcome of planning an edit.
sealed class EditPlan {
  const EditPlan();
}

/// The edit cannot be made, and why.
class EditRefused extends EditPlan {
  const EditRefused(this.reason, {this.detail = const []});

  final EditRefusal reason;

  /// What the reason applies to - the characters that cannot be written, or
  /// how far the replacement overruns, so the message can say something the
  /// person can act on.
  final List<String> detail;
}

/// A byte range of the content stream, and what to put there.
class EditPatch extends EditPlan {
  const EditPatch({
    required this.start,
    required this.end,
    required this.replacement,
    required this.adjustment,
  });

  final int start;
  final int end;

  /// The bytes to write in place of that range.
  final List<int> replacement;

  /// The `TJ` number written after the text, in thousandths of the text size.
  ///
  /// Zero when the replacement happens to be exactly as wide as what it
  /// replaced. Negative widens the gap after it, positive narrows it - the
  /// sign that catches everyone, because the number SUBTRACTS from the
  /// advance.
  final int adjustment;
}

/// Works out how to replace one run's text without moving anything else.
///
/// The replacement is written in the run's OWN font, and the difference in
/// width is absorbed by a `TJ` adjustment so that everything after it on the
/// line stays exactly where it was. Layout is preserved rather than reflowed,
/// which is what editing a total or a date needs and is not a word processor.
EditPlan planTextEdit({
  required TextRun run,
  required String replacement,
  required FontDecoder decoder,
  required double? Function(int code) widthOf,

  /// How much room there is before whatever is drawn next, in points. Null
  /// when it is not known, in which case an overlap cannot be ruled out and
  /// the edit goes ahead - the caller is trusted to have checked or to have
  /// nothing after it.
  double? availableWidth,
}) {
  if (!run.isVisible) {
    return const EditRefused(EditRefusal.notVisible);
  }

  final original = decoder.decode(run.bytes);
  if (original == null) {
    return const EditRefused(EditRefusal.unreadable);
  }

  final missing = decoder.missingFrom(replacement);
  if (missing.isNotEmpty) {
    return EditRefused(
      EditRefusal.missingCharacters,
      detail: missing.toSet().toList(),
    );
  }

  final bytes = decoder.encode(replacement);
  if (bytes == null) {
    return const EditRefused(EditRefusal.missingCharacters);
  }

  final before = _widthOf(run.bytes, decoder, widthOf);
  final after = _widthOf(bytes, decoder, widthOf);
  if (before == null || after == null) {
    return const EditRefused(EditRefusal.unknownWidths);
  }

  // A positive number in a TJ array SUBTRACTS from the advance, so making the
  // text narrower needs a negative one. Getting the sign backwards moves the
  // rest of the line by twice the difference in the wrong direction.
  final adjustment = (after - before).round();

  if (availableWidth != null) {
    final overrun = (after - before) / 1000 * run.fontSize - availableWidth;
    if (overrun > 0) {
      return EditRefused(
        EditRefusal.wouldOverlap,
        detail: ['${overrun.toStringAsFixed(1)} points'],
      );
    }
  }

  return EditPatch(
    start: run.stringStart,
    end: run.stringEnd,
    replacement: bytes,
    adjustment: adjustment,
  );
}

/// The width of [bytes] in thousandths of the text size, or null when any
/// glyph's width is unknown.
///
/// Unknown rather than assumed: a guessed width shifts everything after the
/// edit by however wrong the guess was, and nothing reports it.
double? _widthOf(
  List<int> bytes,
  FontDecoder decoder,
  double? Function(int code) widthOf,
) {
  final codes = _codesOf(bytes, decoder);
  if (codes == null) return null;

  var total = 0.0;
  for (final code in codes) {
    final width = widthOf(code);
    if (width == null) return null;
    total += width;
  }

  return total;
}

/// The codes [bytes] carry, one entry per glyph.
List<int>? _codesOf(List<int> bytes, FontDecoder decoder) {
  final length = decoder is ToUnicodeDecoder ? decoder.codeLength : 1;
  if (bytes.length % length != 0) return null;

  return [
    for (var i = 0; i < bytes.length; i += length)
      [
        for (var b = 0; b < length; b++) bytes[i + b],
      ].fold<int>(0, (value, byte) => (value << 8) | byte),
  ];
}

/// The content stream with [patch] applied, and the show operator rewritten to
/// carry the adjustment.
///
/// The operator becomes `TJ` when it was not already, because only `TJ` can
/// carry the number that keeps the rest of the line where it was.
List<int> applyTextEdit(List<int> stream, TextRun run, EditPatch patch) {
  final out = <int>[
    ...stream.sublist(0, run.operationStart),
    ..._rewrittenOperation(stream, run, patch),
    ...stream.sublist(run.operationEnd),
  ];

  return out;
}

List<int> _rewrittenOperation(List<int> stream, TextRun run, EditPatch patch) {
  final replacement = _literalString(patch.replacement);

  switch (run.source) {
    case TextRunSource.showAdjusted:
      // Already an array: put the new string where the old one was and the
      // adjustment straight after it, leaving every other entry - and every
      // kerning number between them - exactly as it was.
      return [
        ...stream.sublist(run.operationStart, patch.start),
        ...replacement,
        if (patch.adjustment != 0) ..._number(patch.adjustment),
        ...stream.sublist(patch.end, run.operationEnd),
      ];

    case TextRunSource.show:
    case TextRunSource.nextLineShow:
    case TextRunSource.spacedNextLineShow:
      // Anything else has to become an array to carry the adjustment. The
      // operands before the string - the two numbers a `"` takes - are kept.
      final leading = stream.sublist(run.operationStart, patch.start);
      final operator = switch (run.source) {
        TextRunSource.nextLineShow => "'",
        TextRunSource.spacedNextLineShow => '"',
        _ => 'TJ',
      };

      if (patch.adjustment == 0) {
        return [
          ...leading,
          ...replacement,
          ..._ascii(' ${operator == 'TJ' ? 'Tj' : operator}'),
        ];
      }

      // `'` and `"` move to the next line and then show; an array cannot do
      // that, so the move is written out separately and the show becomes TJ.
      return [
        ...leading,
        if (operator != 'TJ') ..._ascii('T* '),
        ..._ascii('['),
        ...replacement,
        ..._number(patch.adjustment),
        ..._ascii(']'),
        ..._ascii(' TJ'),
      ];
  }
}

/// The bytes as a literal string, with the three characters that would end it
/// escaped.
List<int> _literalString(List<int> bytes) => [
  0x28,
  for (final byte in bytes) ...[
    if (byte == 0x28 || byte == 0x29 || byte == 0x5C) 0x5C,
    byte,
  ],
  0x29,
];

List<int> _number(int value) => _ascii(' $value ');

List<int> _ascii(String text) => text.codeUnits;
