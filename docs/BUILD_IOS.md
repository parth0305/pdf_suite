# Building for iOS and iPadOS

iPad uses the same target as iPhone; the interface adapts by width class rather
than by device, so there is no separate iPad build.

## Requirements

- Xcode 16.4 or later
- CocoaPods

## Debug

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d <simulator-id> --dart-define-from-file=config/development.json
```

List simulators with `flutter devices`.

## Release

```bash
flutter build ios --release --dart-define-from-file=config/production.json
```

Signing and provisioning are configured in Xcode and documented separately.
Never commit `.mobileprovision` or `.p12` files; both are gitignored.

## Files-app integration

`Info.plist` sets `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace`, so the app's Documents folder appears
under **On My iPhone → Folio**.

The database deliberately lives in Application Support rather than Documents,
because Documents is user-visible and a user could otherwise delete the library
index.

## Native plugin note

`DocumentHandlePlugin` is declared inside `ios/Runner/AppDelegate.swift` rather
than its own file. A new `.swift` file is not compiled unless it is added to the
Xcode target in `project.pbxproj`, and an uncompiled plugin fails at *runtime*
with `MissingPluginException` rather than at build time.

## Running the integration suite

```bash
flutter test integration_test -d <simulator-id>
```
