@Tags(['presubmit'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Platform permission declarations, which no Dart test can otherwise reach.
///
/// This exists because of a shipping-blocking crash. `image_picker` needs
/// `NSCameraUsageDescription` in `Info.plist`; without it iOS **terminates the
/// app** the instant the camera opens — not an error, not a denied permission,
/// an immediate crash. Folio shipped the scanner without it.
///
/// Nothing in the test suite could have caught it: the scanner is tested
/// against a fake `ScanImageSource`, which is exactly what makes it testable
/// and exactly what stops it reaching the real plugin. When the boundary
/// cannot be crossed in a test, the declaration behind it has to be asserted
/// directly.
void main() {
  group('iOS Info.plist', () {
    late String plist;

    setUpAll(() => plist = File('ios/Runner/Info.plist').readAsStringSync());

    test('declares why it uses the camera', () {
      expect(plist, contains('NSCameraUsageDescription'));
    });

    test('declares why it reads the photo library', () {
      expect(plist, contains('NSPhotoLibraryUsageDescription'));
    });

    // Apple rejects boilerplate, and a user reading "This app needs camera
    // access" learns nothing. The string has to say what Folio does with it.
    test('the explanations name what the data is used for', () {
      for (final key in const [
        'NSCameraUsageDescription',
        'NSPhotoLibraryUsageDescription',
      ]) {
        final at = plist.indexOf(key);
        final value = plist.substring(at, plist.indexOf('</string>', at));

        expect(
          value.length,
          greaterThan(60),
          reason: '$key must explain itself, not just name the permission',
        );
        expect(
          value.toLowerCase(),
          anyOf(contains('folio'), contains('document')),
          reason: '$key should say what it is for',
        );
      }
    });
  });

  // INTERNET is deliberately NOT asserted here: `offline_guarantee_test.dart`
  // already covers it, along with networking dependencies, network APIs in
  // source, and the macOS entitlement. Repeating an assertion in two files is
  // how the two versions of it drift apart.
  group('Android manifest', () {
    // image_picker delegates to the system camera app, which needs no CAMERA
    // permission. Declaring one Folio never uses would make the store listing
    // claim access it does not take.
    test('declares no camera permission it does not use', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, isNot(contains('android.permission.CAMERA')));
    });
  });
}
