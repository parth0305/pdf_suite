import 'dart:convert';
import 'dart:typed_data';

/// How an external file is re-reached after the app restarts.
///
/// A plain path is durable only on Windows. iOS requires a security-scoped
/// bookmark captured at pick time; Android requires a persisted SAF URI grant.
/// Storing a bare path on mobile produces Recents entries that silently fail.
sealed class ExternalHandle {
  const ExternalHandle();
}

/// iOS and macOS security-scoped bookmark.
final class BookmarkHandle extends ExternalHandle {
  const BookmarkHandle(this.data);
  final Uint8List data;
}

/// Android Storage Access Framework URI with a persisted read grant.
final class ContentUriHandle extends ExternalHandle {
  const ContentUriHandle(this.uri);
  final String uri;
}

/// Absolute filesystem path. Durable on Windows; unreliable on mobile.
final class PathHandle extends ExternalHandle {
  const PathHandle(this.path);
  final String path;
}

sealed class DocumentRef {
  const DocumentRef();

  String encode() => jsonEncode(_toJson());

  Map<String, Object?> _toJson();

  static DocumentRef decode(String encoded) {
    final raw = jsonDecode(encoded);
    if (raw is! Map<String, Object?>) {
      throw const FormatException('DocumentRef payload is not an object');
    }

    return switch (raw['kind']) {
      'managed' => ManagedRef(
        relativePath: raw['relativePath']! as String,
        contentHash: raw['contentHash']! as String,
      ),
      'external' => ExternalRef(
        displayName: raw['displayName']! as String,
        handle: _decodeHandle(raw['handle']! as Map<String, Object?>),
      ),
      _ => throw FormatException('Unknown DocumentRef kind: ${raw['kind']}'),
    };
  }

  static ExternalHandle _decodeHandle(Map<String, Object?> json) {
    return switch (json['type']) {
      'bookmark' => BookmarkHandle(base64Decode(json['data']! as String)),
      'contentUri' => ContentUriHandle(json['uri']! as String),
      'path' => PathHandle(json['path']! as String),
      _ => throw FormatException('Unknown handle type: ${json['type']}'),
    };
  }
}

/// A file the app copied into its own library. Always reopenable.
final class ManagedRef extends DocumentRef {
  const ManagedRef({required this.relativePath, required this.contentHash});

  final String relativePath;
  final String contentHash;

  @override
  Map<String, Object?> _toJson() => {
    'kind': 'managed',
    'relativePath': relativePath,
    'contentHash': contentHash,
  };
}

/// A file opened in place. May become unresolvable when the user moves it or
/// the platform revokes the grant.
final class ExternalRef extends DocumentRef {
  const ExternalRef({required this.handle, required this.displayName});

  final ExternalHandle handle;
  final String displayName;

  @override
  Map<String, Object?> _toJson() => {
    'kind': 'external',
    'displayName': displayName,
    'handle': switch (handle) {
      BookmarkHandle(:final data) => {
        'type': 'bookmark',
        'data': base64Encode(data),
      },
      ContentUriHandle(:final uri) => {'type': 'contentUri', 'uri': uri},
      PathHandle(:final path) => {'type': 'path', 'path': path},
    },
  };
}
