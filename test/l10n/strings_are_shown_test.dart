@Tags(['presubmit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every localised string must actually be shown somewhere.
///
/// This exists because of a real bug: three strings written for SP-6b, SP-8a
/// and SP-9 - the OCR "positions are approximate" note, the batch "stopped"
/// message, and the share "this leaves your device" warning - were defined,
/// documented as visible in `FEATURES.md` and `ARCHITECTURE.md`, and never
/// wired to anything. The documentation described messages that did not exist.
///
/// A string nobody shows is not a harmless leftover here. Folio's docs make
/// specific claims about what the app tells you, and this is what keeps those
/// claims true.
void main() {
  test('every defined string is referenced in lib/', () {
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;

    final keys = arb.keys.where((k) => !k.startsWith('@')).toSet();

    // Both accessor styles are in use: `l10n.foo` and
    // `AppLocalizations.of(context)!.foo`. Matching only the first is how the
    // audit that found this bug initially over-reported.
    final source = StringBuffer();
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      // The generated localisations define every key, so counting them as
      // uses would make this test pass unconditionally.
      if (file.path.contains('/l10n/')) continue;
      source.write(file.readAsStringSync());
    }

    final text = source.toString();
    final unused =
        keys.where((k) => !RegExp('\\.$k\\b').hasMatch(text)).toList()..sort();

    expect(
      unused,
      isEmpty,
      reason:
          'These strings are defined but never shown. Either wire them up or '
          'delete them - a string the app never displays cannot back a claim '
          'the documentation makes.',
    );
  });
}
