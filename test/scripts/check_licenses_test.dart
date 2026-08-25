import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/check_licenses.dart';

void main() {
  // A checker that only ever passes is worthless. These assert it actually
  // rejects the licences the project forbids.
  group('classify rejects copyleft', () {
    test('GPL', () {
      expect(
        classify('GNU GENERAL PUBLIC LICENSE Version 3'),
        startsWith('DENIED'),
      );
    });

    test('LGPL', () {
      expect(
        classify('GNU LESSER GENERAL PUBLIC LICENSE'),
        startsWith('DENIED'),
      );
    });

    test('AGPL', () {
      expect(
        classify('GNU AFFERO GENERAL PUBLIC LICENSE'),
        startsWith('DENIED'),
      );
    });

    test('SSPL', () {
      expect(classify('Server Side Public License'), startsWith('DENIED'));
    });
  });

  group('classify rejects the commercial PDF SDKs named in the spec', () {
    for (final vendor in const [
      'Syncfusion',
      'PSPDFKit',
      'Apryse',
      'PDFTron',
      'Foxit',
    ]) {
      test(vendor, () {
        expect(
          classify('$vendor License Agreement'),
          startsWith('DENIED'),
          reason: '$vendor is explicitly excluded by the spec',
        );
      });
    }

    test('the real Syncfusion licence text is rejected', () {
      const real =
          'Syncfusion Flutter PDF package is available under the Syncfusion '
          'Essential Studio program, and can be licensed either under the '
          'Syncfusion Community License Program or the Syncfusion commercial '
          'license.';
      expect(classify(real), startsWith('DENIED'));
    });
  });

  group('classify accepts permissive licences', () {
    test('MIT', () {
      expect(
        classify('Permission is hereby granted, free of charge, to any person'),
        'MIT',
      );
    });

    test('Apache-2.0', () {
      expect(classify('Apache License Version 2.0'), 'Apache-2.0');
    });

    test('BSD-3-Clause', () {
      expect(classify('BSD 3-Clause License'), 'BSD-3-Clause');
    });

    test('unrecognised text is UNKNOWN, not silently accepted', () {
      expect(classify('Some bespoke terms nobody has seen before'), 'UNKNOWN');
    });
  });

  group('audit over the real dependency tree', () {
    test('passes and every direct dependency is documented', () async {
      final result = await Process.run('dart', [
        'run',
        'scripts/check_licenses.dart',
      ]);
      expect(
        result.exitCode,
        0,
        reason: 'licence audit failed:\n${result.stdout}',
      );

      final pubspec = File('pubspec.yaml').readAsStringSync();
      final licenses = File('docs/THIRD_PARTY_LICENSES.md').readAsStringSync();

      // Direct dependencies only: the block between "dependencies:" and
      // "dev_dependencies:".
      final start = pubspec.indexOf('\ndependencies:');
      final end = pubspec.indexOf('\ndev_dependencies:');
      final block = pubspec.substring(start, end);

      final deps = RegExp(r'^  ([a-z_0-9]+):', multiLine: true)
          .allMatches(block)
          .map((m) => m.group(1)!)
          .where((d) => d != 'flutter' && d != 'sdk')
          .toSet();

      final undocumented = deps.where((d) => !licenses.contains(d)).toList();
      expect(
        undocumented,
        isEmpty,
        reason: 'undocumented direct dependencies: $undocumented',
      );
    });
  });
}
