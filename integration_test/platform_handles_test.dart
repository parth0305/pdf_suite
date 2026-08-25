import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/data/file_system/platform_handles.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const handles = PlatformHandles();

  Future<File> tempPdf(String name) async {
    final f = File('${Directory.systemTemp.path}/$name');
    await f.writeAsBytes([37, 80, 68, 70]); // %PDF
    return f;
  }

  group('PlatformHandles', () {
    // Android's Storage Access Framework cannot grant a persistable permission
    // on a filesystem path, so capture() there is only meaningful for a
    // content:// URI supplied by the system picker. These two tests therefore
    // describe genuinely different platform contracts rather than one contract
    // with an exception.
    test(
      'a filesystem path captures and resolves',
      () async {
        final tmp = await tempPdf('handle_probe.pdf');

        final handle = await handles.capture(tmp.path);
        final resolved = await handles.resolveToReadablePath(handle);

        expect(File(resolved).existsSync(), isTrue);
        await handles.release(handle);
        await tmp.delete();
      },
      skip: Platform.isAndroid
          ? 'Android requires a SAF content:// URI, not a path'
          : null,
    );

    test(
      'a deleted file resolves to a typed failure, not a crash',
      () async {
        final tmp = await tempPdf('handle_gone.pdf');
        final handle = await handles.capture(tmp.path);
        await tmp.delete();

        await expectLater(
          handles.resolveToReadablePath(handle),
          throwsA(anyOf(isA<DocumentMoved>(), isA<PermissionRevoked>())),
        );
      },
      skip: Platform.isAndroid
          ? 'Android requires a SAF content:// URI, not a path'
          : null,
    );

    test(
      'Android rejects a filesystem path rather than producing a broken handle',
      () async {
        final tmp = await tempPdf('handle_android.pdf');

        await expectLater(
          handles.capture(tmp.path),
          throwsA(isA<UnsupportedFeature>()),
          reason: 'a path cannot be granted a persistable SAF permission',
        );
        await tmp.delete();
      },
      skip: Platform.isAndroid ? null : 'Android-specific contract',
    );
  });
}
