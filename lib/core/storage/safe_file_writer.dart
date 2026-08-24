import 'dart:io';
import 'dart:math';

/// Thrown when a produced file fails validation before being published.
class WriteValidationException implements Exception {
  const WriteValidationException(this.message);
  final String message;
  @override
  String toString() => 'WriteValidationException: $message';
}

/// Implements the data-safety pipeline required by brief section 37:
///
///   input -> temp working file -> validate -> flush -> atomic rename -> output
///
/// A partially written file is never visible under the destination name, and a
/// failed write never destroys an existing destination.
class SafeFileWriter {
  SafeFileWriter({Random? random}) : _random = random ?? Random();

  final Random _random;

  Future<File> write({
    required File destination,
    required Future<void> Function(File working) produce,
    Future<bool> Function(File working)? validate,
  }) async {
    final parent = destination.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    // Same directory as the destination, so rename stays atomic. A temp file on
    // another volume would silently degrade to a copy.
    final suffix = _random.nextInt(0x7fffffff).toRadixString(16);
    final working = File(
      '${parent.path}${Platform.pathSeparator}'
      '.folio-tmp-$suffix-${destination.uri.pathSegments.last}',
    );

    try {
      await produce(working);

      if (!working.existsSync()) {
        throw const WriteValidationException('producer created no file');
      }

      if (validate != null && !await validate(working)) {
        throw const WriteValidationException('validation rejected the output');
      }

      // Flush to disk before publishing the name.
      final handle = await working.open(mode: FileMode.append);
      await handle.flush();
      await handle.close();

      return await working.rename(destination.path);
    } catch (_) {
      if (working.existsSync()) {
        try {
          await working.delete();
        } catch (_) {
          // Cleanup is best-effort; never mask the original failure.
        }
      }
      rethrow;
    }
  }
}
