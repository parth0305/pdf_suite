import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Suites deliberately left out of the aggregate, with the reason.
const _byHand = {
  // Writes files for a person to open in Word, Excel and PowerPoint. It has
  // no assertions a machine can make about whether Office likes them.
  'office_sample_export_test.dart',
};

void main() {
  // A device suite that is not in the aggregate runs only when somebody names
  // it, which means it stops running the day they stop remembering. The edit
  // suite was missed exactly this way: the check that was supposed to add it
  // looked for `edit_flow_test`, which is a substring of
  // `annotation_edit_flow_test`, so it decided it was already there.
  test('every integration suite is in the aggregate', () {
    final all = File('integration_test/all_tests.dart').readAsStringSync();

    final imported = RegExp(
      r"import '([a-z_0-9]+_test\.dart)'",
    ).allMatches(all).map((m) => m.group(1)!).toSet();

    final files = Directory('integration_test')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('_test.dart'))
        .where((name) => name != 'all_tests.dart')
        .toSet();

    expect(files.difference(imported).difference(_byHand), isEmpty);
  });

  // Importing a suite without calling it is the same silence with an extra
  // step: the analyzer says the import is unused, and nothing else does.
  test('every imported suite is also run', () {
    final all = File('integration_test/all_tests.dart').readAsStringSync();

    final aliases = RegExp(
      r"import '[a-z_0-9]+_test\.dart' as (\w+);",
    ).allMatches(all).map((m) => m.group(1)!).toSet();

    final run = RegExp(
      r'group\(\s*.[a-z_0-9]+.,\s*(\w+)\.main',
    ).allMatches(all).map((m) => m.group(1)!).toSet();

    expect(aliases.difference(run), isEmpty);
  });

  test('nothing on the by-hand list has quietly disappeared', () {
    for (final name in _byHand) {
      expect(File('integration_test/$name').existsSync(), isTrue, reason: name);
    }
  });
}
