import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';

void main() {
  late Directory sandbox;
  late SafeFileWriter writer;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('safe_writer_test');
    writer = SafeFileWriter();
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  group('SafeFileWriter', () {
    test('writes the destination file on success', () async {
      final dest = File('${sandbox.path}/out.bin');

      final result = await writer.write(
        destination: dest,
        produce: (working) => working.writeAsBytes([1, 2, 3]),
      );

      expect(result.existsSync(), isTrue);
      expect(await result.readAsBytes(), [1, 2, 3]);
    });

    test('leaves no temp files behind on success', () async {
      final dest = File('${sandbox.path}/out.bin');
      await writer.write(
        destination: dest,
        produce: (working) => working.writeAsBytes([1, 2, 3]),
      );

      final strays = sandbox.listSync().whereType<File>().where(
        (f) => f.path.contains('.folio-tmp'),
      );
      expect(strays, isEmpty);
    });

    test('does not create the destination when produce throws', () async {
      final dest = File('${sandbox.path}/never.bin');

      await expectLater(
        writer.write(
          destination: dest,
          produce: (working) async =>
              throw const FileSystemException('disk died'),
        ),
        throwsA(isA<Exception>()),
      );

      expect(
        dest.existsSync(),
        isFalse,
        reason: 'a failed write must never leave a partial destination',
      );
    });

    test('cleans up temp files when produce throws', () async {
      final dest = File('${sandbox.path}/never.bin');
      try {
        await writer.write(
          destination: dest,
          produce: (working) async =>
              throw const FileSystemException('disk died'),
        );
      } catch (_) {}

      final strays = sandbox.listSync().whereType<File>().where(
        (f) => f.path.contains('.folio-tmp'),
      );
      expect(strays, isEmpty);
    });

    test(
      'rejects the write when validation fails, preserving any existing file',
      () async {
        final dest = File('${sandbox.path}/existing.bin');
        await dest.writeAsBytes([9, 9, 9]);

        await expectLater(
          writer.write(
            destination: dest,
            produce: (working) => working.writeAsBytes([1, 2, 3]),
            validate: (working) async => false,
          ),
          throwsA(isA<Exception>()),
        );

        expect(
          await dest.readAsBytes(),
          [9, 9, 9],
          reason: 'a rejected write must not clobber the original',
        );
      },
    );

    test(
      'places the temp file on the same volume as the destination',
      () async {
        final dest = File('${sandbox.path}/out.bin');
        String? observedTempDir;

        await writer.write(
          destination: dest,
          produce: (working) async {
            observedTempDir = working.parent.path;
            await working.writeAsBytes([1]);
          },
        );

        expect(
          observedTempDir,
          sandbox.path,
          reason: 'cross-volume temp makes rename non-atomic',
        );
      },
    );
  });
}
