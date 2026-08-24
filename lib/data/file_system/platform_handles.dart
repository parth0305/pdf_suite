import 'dart:io';

import 'package:flutter/services.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/models/document_ref.dart';

/// Captures and resolves durable references to files the app does not own.
///
/// Only the secondary open-in-place flow needs this. The default import flow
/// copies bytes into the app library and produces a [ManagedRef], which needs
/// no platform support at all.
class PlatformHandles {
  const PlatformHandles();

  static const MethodChannel _channel = MethodChannel('dev.folio.app/handles');

  /// Converts a freshly picked path or URI into a handle that survives relaunch.
  ///
  /// On Android the argument **must** be a Storage Access Framework
  /// `content://` URI obtained from the system picker. A plain filesystem path
  /// cannot be granted a persistable permission, and is rejected rather than
  /// silently producing a handle that fails on the next launch.
  Future<ExternalHandle> capture(String pathOrUri) async {
    if (Platform.isWindows || Platform.isLinux) {
      return PathHandle(pathOrUri);
    }
    try {
      if (Platform.isAndroid) {
        if (!pathOrUri.startsWith('content://')) {
          throw const UnsupportedFeature(
            technicalDetail:
                'Android open-in-place requires a SAF content:// URI, '
                'not a filesystem path',
          );
        }
        await _channel.invokeMethod<void>('persistUriPermission', {
          'uri': pathOrUri,
        });
        return ContentUriHandle(pathOrUri);
      }
      final data = await _channel.invokeMethod<Uint8List>('createBookmark', {
        'path': pathOrUri,
      });
      if (data == null) {
        throw const PermissionRevoked(
          technicalDetail: 'bookmark creation returned null',
        );
      }
      return BookmarkHandle(data);
    } on PlatformException catch (e) {
      throw PermissionRevoked(technicalDetail: '${e.code}: ${e.message}');
    }
  }

  /// Returns a path the Dart side can read. Callers must call [release] after.
  Future<String> resolveToReadablePath(ExternalHandle handle) async {
    try {
      return switch (handle) {
        PathHandle(:final path) => await _requireExists(path),
        ContentUriHandle(:final uri) => await _invokeString('openContentUri', {
          'uri': uri,
        }),
        BookmarkHandle(:final data) => await _invokeString('resolveBookmark', {
          'data': data,
        }),
      };
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'stale' ||
        'revoked' => PermissionRevoked(technicalDetail: e.message ?? e.code),
        'missing' => DocumentMoved(technicalDetail: e.message ?? e.code),
        _ => UnknownFailure(technicalDetail: '${e.code}: ${e.message}'),
      };
    }
  }

  Future<void> release(ExternalHandle handle) async {
    if (handle is BookmarkHandle) {
      await _channel.invokeMethod<void>('stopAccessing', {'data': handle.data});
    }
  }

  Future<String> _requireExists(String path) async {
    if (!File(path).existsSync()) {
      throw const DocumentMoved(technicalDetail: 'path no longer exists');
    }
    return path;
  }

  Future<String> _invokeString(String method, Map<String, Object?> args) async {
    final result = await _channel.invokeMethod<String>(method, args);
    if (result == null) {
      throw const DocumentMoved(technicalDetail: 'resolve returned null');
    }
    return result;
  }
}
