import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the app-owned directories. The library root holds imported
/// documents; the temp root holds transient working files.
class AppDirectories {
  const AppDirectories();

  Future<Directory> libraryRoot() async {
    final base = await getApplicationSupportDirectory();
    return _ensure(Directory(p.join(base.path, 'library')));
  }

  Future<Directory> tempRoot() async {
    final base = await getApplicationSupportDirectory();
    return _ensure(Directory(p.join(base.path, 'tmp')));
  }

  Future<Directory> _ensure(Directory dir) async {
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
