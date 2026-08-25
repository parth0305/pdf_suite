# Building for Windows

## This cannot be done on the development machine

Flutter Windows desktop builds require Windows plus Visual Studio 2022 with the
"Desktop development with C++" workload. The development machine for this
project is an Intel Mac, so Windows binaries are produced **only** by CI.

## How Windows is built

`.github/workflows/ci.yml`, job `build-windows`, on the `windows-latest` runner:

```yaml
- run: flutter pub get
- run: dart run build_runner build --delete-conflicting-outputs
- run: flutter test
- run: flutter build windows --debug --dart-define-from-file=config/development.json
```

`build_runner` must run before `flutter test`, because `*.g.dart` is gitignored
and the analyzer would otherwise see missing `part` files.

## On an actual Windows machine

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build windows --release --dart-define-from-file=config/production.json
```

Output: `build\windows\x64\runner\Release\`.

## What CI does not prove

Compilation and unit tests only. Mouse, keyboard, touchscreen, File Explorer
drag-and-drop and printing are entirely unverified. Treat any Windows-specific
bug report as plausible until someone runs it.

If a Windows build starts failing after a dependency change, suspect **Dart
native assets** first: both `pdfrx` (PDFium) and `sqlite3` build through build
hooks under MSVC.
