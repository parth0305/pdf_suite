// Fails the build if any dependency carries a copyleft or commercial licence.
//
// Reads .dart_tool/package_config.json, locates each package in the pub cache,
// and inspects its LICENSE file. Prints every package with its detected licence
// so the CI log doubles as an audit trail.
import 'dart:convert';
import 'dart:io';

/// Substrings that disqualify a dependency outright.
const Map<String, String> denied = {
  'GNU GENERAL PUBLIC LICENSE': 'GPL',
  'GNU LESSER GENERAL PUBLIC': 'LGPL',
  'GNU AFFERO': 'AGPL',
  'Server Side Public License': 'SSPL',
  'Syncfusion': 'Syncfusion proprietary',
  'PSPDFKit': 'PSPDFKit commercial',
  'Apryse': 'Apryse commercial',
  'PDFTron': 'PDFTron commercial',
  'Foxit': 'Foxit commercial',
};

/// Recognised permissive licences, longest-match first so "BSD 3-Clause" is not
/// reported merely as "BSD".
const List<(String, String)> permissive = [
  ('Apache License', 'Apache-2.0'),
  ('BSD 3-Clause', 'BSD-3-Clause'),
  ('BSD-3-Clause', 'BSD-3-Clause'),
  ('BSD 2-Clause', 'BSD-2-Clause'),
  ('Redistribution and use in source and binary forms', 'BSD'),
  ('MIT License', 'MIT'),
  ('Permission is hereby granted, free of charge', 'MIT'),
  ('Mozilla Public License', 'MPL-2.0'),
  ('public domain', 'Public domain'),
  ('Unlicense', 'Unlicense'),
  ('Zlib', 'Zlib'),
];

String classify(String text) {
  for (final entry in denied.entries) {
    if (text.contains(entry.key)) return 'DENIED: ${entry.value}';
  }
  for (final (needle, name) in permissive) {
    if (text.contains(needle)) return name;
  }
  return 'UNKNOWN';
}

Future<int> run() async {
  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) {
    stderr.writeln('package_config.json missing - run flutter pub get first.');
    return 2;
  }

  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = (config['packages'] as List).cast<Map<String, dynamic>>();

  final violations = <String>[];
  final unknown = <String>[];
  final rows = <(String, String)>[];

  for (final pkg in packages) {
    final name = pkg['name'] as String;
    if (name == 'folio') continue;

    final rootUri = pkg['rootUri'] as String;
    final resolved = rootUri.startsWith('file://')
        ? Uri.parse(rootUri).toFilePath()
        : Directory('.dart_tool').uri.resolve(rootUri).toFilePath();

    String? text;
    for (final candidate in const ['LICENSE', 'LICENSE.md', 'LICENSE.txt']) {
      final f = File('$resolved/$candidate');
      if (f.existsSync()) {
        text = f.readAsStringSync();
        break;
      }
    }

    if (text == null) {
      // Flutter SDK packages carry the SDK's own BSD-3 licence.
      if (resolved.contains('/flutter/packages/') ||
          resolved.contains('\\flutter\\packages\\')) {
        rows.add((name, 'BSD-3-Clause (Flutter SDK)'));
        continue;
      }
      rows.add((name, 'NO LICENSE FILE'));
      unknown.add(name);
      continue;
    }

    final verdict = classify(text);
    rows.add((name, verdict));
    if (verdict.startsWith('DENIED')) {
      violations.add('$name -> $verdict');
    } else if (verdict == 'UNKNOWN') {
      unknown.add(name);
    }
  }

  rows.sort((a, b) => a.$1.compareTo(b.$1));
  stdout.writeln('Dependency licence audit (${rows.length} packages)');
  stdout.writeln('-' * 64);
  for (final (name, verdict) in rows) {
    stdout.writeln('  ${name.padRight(38)} $verdict');
  }
  stdout.writeln('-' * 64);

  if (violations.isNotEmpty) {
    stdout.writeln('\nFAIL: copyleft or commercial dependencies present:');
    for (final v in violations) {
      stdout.writeln('  $v');
    }
    return 1;
  }

  if (unknown.isNotEmpty) {
    stdout.writeln(
      '\nFAIL: ${unknown.length} package(s) could not be classified. '
      'Classify them manually and record them in '
      'docs/THIRD_PARTY_LICENSES.md:',
    );
    for (final u in unknown) {
      stdout.writeln('  $u');
    }
    return 1;
  }

  stdout.writeln('\nPASS: all dependencies are permissively licensed.');
  return 0;
}

Future<void> main() async => exitCode = await run();
