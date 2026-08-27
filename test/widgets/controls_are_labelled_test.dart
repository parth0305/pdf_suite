@Tags(['presubmit'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The extent of the constructor call starting at [open] (the index of its
/// `(`), by balancing parentheses and skipping string literals.
///
/// A window of N characters is not good enough: an earlier version of this
/// check used one and reported eleven false positives, because `tooltip:`
/// often sits after the `icon:` line and past the window's edge.
int _closingParen(String source, int open) {
  var depth = 0;
  var i = open;

  while (i < source.length) {
    final c = source[i];

    if (c == "'" || c == '"') {
      final quote = c;
      i++;
      while (i < source.length && source[i] != quote) {
        if (source[i] == r'\') i++;
        i++;
      }
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }

  return source.length;
}

void main() {
  /// An `IconButton` with no tooltip is announced by a screen reader as
  /// "button" and nothing else. Folio is a document app: a person who cannot
  /// see the icon still has to be able to tell Delete from Favourite.
  test('every IconButton has a tooltip', () {
    final unlabelled = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();

      for (final match in RegExp('IconButton').allMatches(source)) {
        final open = source.indexOf('(', match.end);
        if (open < 0) continue;
        // `IconButton` also appears in type positions and comments.
        if (open != match.end) continue;

        final body = source.substring(open, _closingParen(source, open));
        if (body.contains('tooltip:')) continue;

        final line = source.substring(0, match.start).split('\n').length;
        unlabelled.add('${entity.path}:$line');
      }
    }

    expect(
      unlabelled,
      isEmpty,
      reason:
          'These buttons have no tooltip, so a screen reader announces them '
          'as "button" with no further description.',
    );
  });
}
