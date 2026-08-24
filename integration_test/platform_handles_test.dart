import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/data/file_system/platform_handles.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const handles = PlatformHandles();

  group('PlatformHandles', () {
    test('captures and resolves a handle for a real file', () async {
      final tmp = File('${Directory.systemTemp.path}/handle_probe.pdf');
      await tmp.writeAsBytes([37, 80, 68, 70]); // %PDF

      final handle = await handles.capture(tmp.path);
      final resolved = await handles.resolveToReadablePath(handle);

      expect(File(resolved).existsSync(), isTrue);
      await handles.release(handle);
      await tmp.delete();
    });

    test('a deleted file resolves to a typed failure, not a crash', () async {
      final tmp = File('${Directory.systemTemp.path}/handle_gone.pdf');
      await tmp.writeAsBytes([37, 80, 68, 70]);
      final handle = await handles.capture(tmp.path);
      await tmp.delete();

      await expectLater(
        handles.resolveToReadablePath(handle),
        throwsA(anyOf(isA<DocumentMoved>(), isA<PermissionRevoked>())),
      );
    });
  });
}
