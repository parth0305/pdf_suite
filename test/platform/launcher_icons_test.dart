import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The dimensions Android expects at each density. Adaptive layers are 108dp
/// square; the legacy icon is 48dp.
const _adaptive = {
  'mdpi': 108,
  'hdpi': 162,
  'xhdpi': 216,
  'xxhdpi': 324,
  'xxxhdpi': 432,
};
const _legacy = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

const _res = 'android/app/src/main/res';

/// Width and height from a PNG header, without a decoder.
({int width, int height}) pngSize(File file) {
  final bytes = file.readAsBytesSync();
  final view = ByteData.sublistView(Uint8List.fromList(bytes));

  return (width: view.getUint32(16), height: view.getUint32(20));
}

void main() {
  group('android launcher icon', () {
    // Without this file Android 8+ masks the finished artwork itself - a
    // rounded square trimmed into a circle on a background the launcher
    // picked, which is not what the icon looks like anywhere else.
    test('declares an adaptive icon', () {
      final xml = File('$_res/mipmap-anydpi-v26/ic_launcher.xml');

      expect(xml.existsSync(), isTrue);
      expect(xml.readAsStringSync(), contains('<adaptive-icon'));
    });

    test('the adaptive icon names all three layers', () {
      final xml = File(
        '$_res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();

      expect(xml, contains('<background'));
      expect(xml, contains('<foreground'));
      // Android 13 themed icons. Without it the launcher shrinks the whole
      // icon onto a grey plate.
      expect(xml, contains('<monochrome'));
    });

    test('every layer the adaptive icon names exists', () {
      final xml = File(
        '$_res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();

      for (final match in RegExp(
        r'android:drawable="@(mipmap|drawable)/(\w+)"',
      ).allMatches(xml)) {
        final kind = match.group(1)!;
        final name = match.group(2)!;

        final found = kind == 'drawable'
            ? File('$_res/drawable/$name.xml').existsSync()
            : _adaptive.keys.every(
                (d) => File('$_res/mipmap-$d/$name.png').existsSync(),
              );

        expect(found, isTrue, reason: '$kind/$name');
      }
    });

    for (final entry in _adaptive.entries) {
      test('the ${entry.key} adaptive layers are 108dp square', () {
        for (final layer in ['foreground', 'monochrome']) {
          final size = pngSize(
            File('$_res/mipmap-${entry.key}/ic_launcher_$layer.png'),
          );

          expect(size.width, entry.value, reason: layer);
          expect(size.height, entry.value, reason: layer);
        }
      });
    }

    // Pre-26 devices still use the flat PNG, so it has to stay.
    for (final entry in _legacy.entries) {
      test('the ${entry.key} legacy icon is still there and 48dp', () {
        final size = pngSize(File('$_res/mipmap-${entry.key}/ic_launcher.png'));

        expect(size.width, entry.value);
        expect(size.height, entry.value);
      });
    }
  });

  // The name under the icon. iOS shows "Folio"; Android showed "folio", which
  // is the Flutter template's lowercased project name rather than a decision.
  test('both platforms label the app the same way', () {
    final android = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final ios = File('ios/Runner/Info.plist').readAsStringSync();

    expect(android, contains('android:label="Folio"'));
    expect(
      RegExp(
        r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
      ).firstMatch(ios)!.group(1),
      'Folio',
    );
  });
}
