# Building for Android

## Requirements

- Android SDK with platform 35 and build-tools 35
- JDK 17
- An x86_64 system image if the host is an Intel Mac — `arm64-v8a` images will
  not run

## Debug

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --debug --dart-define-from-file=config/development.json
```

## Release

```bash
flutter build apk --release --dart-define-from-file=config/production.json
# or, for Play:
flutter build appbundle --release --dart-define-from-file=config/production.json
```

Signing is configured separately; `android/key.properties` and any keystore are
gitignored and must never be committed.

## Creating an emulator

```bash
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export JAVA_HOME="/usr/local/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home"

sdkmanager "system-images;android-35;google_apis;x86_64"
avdmanager create avd -n pixel_api35 \
  -k "system-images;android-35;google_apis;x86_64" -d pixel_6
flutter emulators --launch pixel_api35
```

`avdmanager` reports `Valid system image paths are: null` unless
`ANDROID_SDK_ROOT` is exported, even when the image is installed.

## Running the integration suite

```bash
flutter test integration_test -d emulator-5554
```

Two handle tests are skipped on Android by design: the Storage Access Framework
cannot grant a persistable permission on a filesystem path, so those tests
describe an iOS/desktop contract that does not apply.
