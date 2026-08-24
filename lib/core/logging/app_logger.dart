import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:folio/core/constants/app_config.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:logging/logging.dart';

/// Local-only structured logging.
///
/// Records operation, timing, size, result and error code (brief section 38).
///
/// **Never** accepts document content, passwords, filenames, or paths. File
/// identity is passed as a hash produced by [hashIdentity]. The API takes
/// `fileHash`, not `fileName`, so leaking identity requires deliberate effort.
class AppLogger {
  AppLogger._(this._logger, this._captureBuffer);

  factory AppLogger.forTesting() =>
      AppLogger._(Logger('folio.test'), <LogRecord>[]);

  factory AppLogger.production() => AppLogger._(
    Logger('folio'),
    AppConfig.current.isProduction ? null : <LogRecord>[],
  );

  final Logger _logger;
  final List<LogRecord>? _captureBuffer;

  List<LogRecord> get buffer => List.unmodifiable(_captureBuffer ?? const []);

  /// A short, stable, non-reversible identifier for a file.
  String hashIdentity(String raw) =>
      sha256.convert(utf8.encode(raw)).toString().substring(0, 16);

  void operationStart(
    String operation, {
    String? fileHash,
    int? fileSizeBytes,
  }) {
    _emit(
      Level.INFO,
      _compose('start', operation, {
        if (fileHash != null) 'file': fileHash,
        if (fileSizeBytes != null) 'bytes': '$fileSizeBytes',
      }),
    );
  }

  void operationEnd(
    String operation, {
    required bool success,
    AppFailure? failure,
    Duration? elapsed,
  }) {
    _emit(
      success ? Level.INFO : Level.WARNING,
      _compose('end', operation, {
        'result': success ? 'success' : 'failure',
        if (elapsed != null) 'ms': '${elapsed.inMilliseconds}',
        if (failure != null) 'code': failure.code,
        if (failure?.technicalDetail != null)
          'detail': failure!.technicalDetail!,
      }),
    );
  }

  String _compose(String phase, String operation, Map<String, String> fields) {
    final parts = [
      '$phase op=$operation',
      ...fields.entries.map((e) => '${e.key}=${e.value}'),
    ];
    return parts.join(' ');
  }

  void _emit(Level level, String message) {
    final record = LogRecord(level, message, _logger.name);
    _captureBuffer?.add(record);
    _logger.log(level, message);
  }
}
