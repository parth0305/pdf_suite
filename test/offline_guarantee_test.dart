import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Offline-first is a property of the build, not a promise in a README.
///
/// These tests fail if anyone adds a networking dependency, a network API
/// call, or the Android INTERNET permission to a shipping manifest. They are
/// deliberately cheap so they run on every CI push.
void main() {
  group('the app cannot reach the network', () {
    test('no networking package is a direct dependency', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final start = pubspec.indexOf('\ndependencies:');
      final end = pubspec.indexOf('\ndev_dependencies:');
      final block = pubspec.substring(start, end);

      const networking = [
        'http:',
        'dio:',
        'web_socket_channel:',
        'firebase_core:',
        'googleapis:',
        'grpc:',
        'supabase_flutter:',
      ];
      for (final pkg in networking) {
        expect(
          block,
          isNot(contains('\n  $pkg')),
          reason: '$pkg would give the app network access',
        );
      }
    });

    test('no source file uses a network API', () {
      final offenders = <String>[];
      final pattern = RegExp(
        r'\b(HttpClient|WebSocket|InternetAddress|Image\.network|NetworkImage)\b'
        r"|package:http/|dart:html",
      );

      for (final dir in ['lib', 'scripts']) {
        for (final entity in Directory(dir).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.endsWith('.g.dart')) continue;
          if (pattern.hasMatch(entity.readAsStringSync())) {
            offenders.add(entity.path);
          }
        }
      }

      expect(offenders, isEmpty, reason: 'network API used in: $offenders');
    });

    test('the shipping Android manifest declares no INTERNET permission', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(
        manifest,
        isNot(contains('android.permission.INTERNET')),
        reason:
            'the release manifest must not request INTERNET; Android itself '
            'then enforces that the app cannot reach the network',
      );
    });

    test('the macOS release entitlements grant no outgoing network', () {
      final file = File('macos/Runner/Release.entitlements');
      if (!file.existsSync()) return;

      expect(
        file.readAsStringSync(),
        isNot(contains('com.apple.security.network.client')),
        reason: 'release builds must not be entitled to outgoing connections',
      );
    });
  });
}
