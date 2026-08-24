# SP-1 Foundation + Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an offline, read-only PDF reader for iPhone, iPad, Android and Windows that opens, searches, and displays PDFs without ever modifying them.

**Architecture:** Flutter app in clean layers — `features/` (UI) → `domain/` (pure Dart, no Flutter or native imports) → `data/` (drift, file system, platform channels). All PDF work goes through a `PdfEngine` interface with two implementations: `PdfrxEngine` (PDFium, production) and `FakePdfEngine` (unit tests, no native code). The interface exposes **no write method**, making "SP-1 cannot alter a PDF" a compile-time guarantee.

**Tech Stack:** Flutter 3.41.9 · Dart 3.11.5 · pdfrx 2.4.7 (MIT, bundles PDFium BSD-3) · flutter_riverpod 3.4.2 (MIT) · drift 2.34.3 + drift_flutter 0.3.1 (MIT) · file_selector 1.1.0 (BSD-3) · path_provider 2.1.6 (BSD-3) · intl 0.20.3 (BSD-3) · logging 1.3.0 (BSD-3)

**Spec:** `docs/superpowers/specs/2026-08-24-sp1-foundation-viewer-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Zero AI.** No LLM, no chat-with-PDF, no AI OCR, no cloud AI API, no summarization. Not in code, not in dependencies, not in copy.
- **Zero paid or proprietary dependencies.** No Adobe SDK, PSPDFKit, Apryse/PDFTron, Foxit, Nitro, paid OCR, paid analytics. **`syncfusion_flutter_pdf` is permanently rejected** — its LICENSE requires a Syncfusion Community licence (revenue < USD 1M, < 5 developers) or a paid commercial licence.
- **Permissive licences only.** MIT, BSD, Apache-2.0. No GPL, LGPL, or AGPL. Every dependency added must be recorded in `docs/THIRD_PARTY_LICENSES.md` in the same commit that adds it.
- **No mandatory network.** Core functionality must work with networking fully disabled. No cloud backend, no account, no telemetry.
- **No Acrobat imitation.** No copied UI, branding, icons, or copyrighted assets.
- **SP-1 never modifies PDF content.** Whole-file library operations (copy, rename, move, delete) are allowed and go through `SafeFileWriter`. Parsing or re-encoding a PDF's byte stream is out of scope.
- **Originals are never destroyed.** Every operation produces a new output. No in-place overwrite without explicit user choice (and SP-1 offers none).
- **Never log document content.** No PDF text, passwords, titles, filenames, or paths in logs. File identity is logged as a hash only.
- **No hard-coded user-facing strings.** All UI text goes through ARB localization from the first commit. English only in SP-1.
- **PDFs are untrusted input.** Malformed files must fail safely with a friendly message, never a crash and never a raw stack trace in the UI. PDF-embedded JavaScript is never executed.
- **Minimum touch target 48x48dp. Visible keyboard focus indicators. Screen-reader labels on every interactive element.**
- **Layout branches on width class, never on `Platform.isX`.** Platform checks are permitted only for genuine capability differences (pickers, permissions).
- **Never claim a feature works without running it.** "Implemented" requires coded, compiled, tested, and manually verified.

### Known platform risk

Both `pdfrx` and `sqlite3` (via `drift_flutter`) now use Dart's **native assets / build hooks** mechanism (`hook/`, `code_assets`, `native_toolchain_c`) rather than classic Flutter plugins. The iOS build emits a non-fatal `Target native_assets required define SdkRoot but it was not provided`. This is the most likely source of cross-platform build failure, especially on the Windows CI runner which no human can debug interactively. **Task 1 wires CI before any feature exists**, so this surfaces on day one rather than at release.

### Verification environment

- **Primary demo target:** iPhone 16 Plus simulator, `DFC5606D-37F0-4176-A73D-B8214C7F820F` (iOS 18.6). Demo on the simulator at the end of every stage.
- **Android:** no AVD exists yet. Task 1 creates one. Until then, no Android claim may be made.
- **Windows:** no local machine. GitHub Actions `windows-latest` only — compile and unit tests. Manual Windows QA is impossible and is a recorded limitation.

---

## File Structure

| Path | Responsibility |
|---|---|
| `lib/main.dart` | Entry point; flavor selection; runs `FolioApp` |
| `lib/app.dart` | Root widget, theme wiring, router, localization delegates |
| `lib/core/constants/breakpoints.dart` | Width-class thresholds |
| `lib/core/errors/app_failure.dart` | Sealed failure hierarchy |
| `lib/core/errors/failure_messages.dart` | Failure → localized user message |
| `lib/core/logging/app_logger.dart` | Structured local logging with redaction rules |
| `lib/core/storage/safe_file_writer.dart` | Atomic write pipeline (brief §37) |
| `lib/core/storage/app_directories.dart` | Library root, temp root resolution |
| `lib/core/theme/app_theme.dart` | Light + dark Material 3 themes |
| `lib/domain/engine/pdf_engine.dart` | `PdfEngine` interface — no write methods |
| `lib/domain/engine/pdf_types.dart` | `PdfDocumentHandle`, `PageText`, `OutlineNode`, `RenderedPage`, `DocumentPermissions` |
| `lib/domain/models/document_ref.dart` | `DocumentRef` sealed class, `ExternalHandle` |
| `lib/domain/models/library_document.dart` | Library entry model |
| `lib/domain/repositories/library_repository.dart` | Library repository interface |
| `lib/domain/services/document_sorter.dart` | Sort + filter logic (pure) |
| `lib/data/local/app_database.dart` | drift database + tables |
| `lib/data/local/library_dao.dart` | Library queries |
| `lib/data/file_system/document_resolver.dart` | `DocumentRef` → bytes, typed failures |
| `lib/data/file_system/platform_handles.dart` | iOS bookmarks / Android SAF channel |
| `lib/data/repositories/library_repository_impl.dart` | Import-copies-in implementation |
| `lib/engine/pdfrx_engine.dart` | `PdfEngine` over pdfrx |
| `lib/features/home/…` | Library, recents, favorites, search, sort |
| `lib/features/viewer/…` | Reader, thumbnails, search, selection, outline |
| `lib/features/settings/…` | Theme, about, licences |
| `lib/widgets/adaptive_scaffold.dart` | Width-class navigation shell |
| `test/fakes/fake_pdf_engine.dart` | `PdfEngine` test double |
| `scripts/make_fixtures.dart` | Generates `test_documents/` |
| `scripts/check_licenses.dart` | Fails CI on non-permissive licences |

---

# Stage 1 — Bootstrap and core primitives

Ends with: an app that launches on the simulator, shows a themed adaptive shell, and has green CI on three runners.

---

### Task 1: Flutter project, flavors, and CI on day one

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `lib/app.dart`
- Platforms: `android`, `ios`, `windows`, **`macos`** — macOS is not a shipping target, but it is the only desktop this machine can build, so it stands in for manual verification of the expanded layout that Windows CI cannot provide
- Create: `config/development.json`, `config/testing.json`, `config/production.json`
- Create: `lib/core/constants/app_config.dart`
- Create: `.github/workflows/ci.yml`
- Test: `test/core/app_config_test.dart`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `AppConfig` with `static AppConfig get current`, fields `String environment`, `bool verboseLogging`; app package name `folio`; bundle id `dev.folio.app`

CI is written **before any feature** because both `pdfrx` and `sqlite3` use Dart native assets, and the Windows runner is the only Windows verification that will ever exist.

- [ ] **Step 1: Scaffold the Flutter project into the existing repo**

The repo already contains `.git`, `docs/`, and `scripts/`. Scaffold in place:

```bash
cd /Users/user/pdf_suite
flutter create --project-name folio --org dev.folio \
  --platforms=android,ios,windows,macos --overwrite .
```

- [ ] **Step 2: Correct the bundle identifier to `dev.folio.app`**

`flutter create` produces `dev.folio.folio`. Fix all occurrences:

```bash
cd /Users/user/pdf_suite
# iOS (Debug, Release, Profile configurations)
sed -i '' 's/dev\.folio\.folio/dev.folio.app/g' ios/Runner.xcodeproj/project.pbxproj
# Android
sed -i '' 's/dev\.folio\.folio/dev.folio.app/g' android/app/build.gradle.kts
# Verify none remain (RunnerTests keeps its own suffix, which is expected)
grep -rn "dev.folio.folio" ios/ android/ || echo "OK: no stale identifiers"
```

Expected: `OK: no stale identifiers`, or only `dev.folio.app.RunnerTests` remaining.

- [ ] **Step 3: Write the config files**

Flavors use `--dart-define-from-file` rather than native Android product flavors and iOS schemes. This keeps one build configuration per platform, works identically on all four targets, and avoids per-platform scheme maintenance. The tradeoff: all environments share one bundle id, so they cannot be installed side by side. That is acceptable for SP-1.

`config/development.json`:
```json
{
  "APP_ENV": "development",
  "VERBOSE_LOGGING": true
}
```

`config/testing.json`:
```json
{
  "APP_ENV": "testing",
  "VERBOSE_LOGGING": true
}
```

`config/production.json`:
```json
{
  "APP_ENV": "production",
  "VERBOSE_LOGGING": false
}
```

- [ ] **Step 4: Write the failing test for AppConfig**

`test/core/app_config_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/constants/app_config.dart';

void main() {
  group('AppConfig', () {
    test('defaults to development when no dart-define is supplied', () {
      expect(AppConfig.current.environment, 'development');
    });

    test('production config disables verbose logging', () {
      const prod = AppConfig(environment: 'production', verboseLogging: false);
      expect(prod.verboseLogging, isFalse);
      expect(prod.isProduction, isTrue);
    });

    test('development config is not production', () {
      const dev = AppConfig(environment: 'development', verboseLogging: true);
      expect(dev.isProduction, isFalse);
    });
  });
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `flutter test test/core/app_config_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:folio/core/constants/app_config.dart'`

- [ ] **Step 6: Implement AppConfig**

`lib/core/constants/app_config.dart`:
```dart
/// Build-time configuration, supplied via `--dart-define-from-file`.
///
/// Defaults to development so that a bare `flutter run` works without flags.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.verboseLogging,
  });

  final String environment;
  final bool verboseLogging;

  bool get isProduction => environment == 'production';

  static const AppConfig current = AppConfig(
    environment: String.fromEnvironment('APP_ENV', defaultValue: 'development'),
    verboseLogging: bool.fromEnvironment('VERBOSE_LOGGING', defaultValue: true),
  );
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `flutter test test/core/app_config_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 8: Tighten the analyzer**

`analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    - always_declare_return_types
    - avoid_print
    - prefer_const_constructors
    - prefer_final_locals
    - require_trailing_commas
    - unawaited_futures
    - use_super_parameters
```

`avoid_print` matters: it forces all output through `AppLogger` (Task 3), which is what keeps document content out of logs.

- [ ] **Step 9: Write the CI workflow**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main, develop]

env:
  FLUTTER_VERSION: '3.41.9'

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
      - run: flutter pub get
      - run: dart format --set-exit-if-changed lib test
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage
      - run: dart run scripts/check_licenses.dart

  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
      - run: flutter pub get
      - run: flutter build apk --debug --dart-define-from-file=config/development.json

  build-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
      - run: flutter pub get
      - run: flutter build ios --debug --no-codesign --dart-define-from-file=config/development.json

  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
      - run: flutter pub get
      - run: flutter test
      - run: flutter build windows --debug --dart-define-from-file=config/development.json
```

`build-windows` is the only Windows verification this project will ever have. If it fails after `pdfrx` or `drift` is added, suspect native assets first.

- [ ] **Step 10: Write a placeholder licence checker so CI is green**

`scripts/check_licenses.dart` gets its real implementation in Task 20. For now it must exist and pass:
```dart
/// Fails the build if any dependency carries a copyleft licence.
/// Full implementation lands in Task 20; this stub keeps CI green until then.
void main() {
  // ignore: avoid_print
  print('License check: stub — full audit implemented in Task 20.');
}
```

- [ ] **Step 11: Create the Android AVD (no Android claim is valid without it)**

```bash
~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager \
  "system-images;android-35;google_apis;x86_64"
~/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager create avd \
  -n pixel_api35 -k "system-images;android-35;google_apis;x86_64" -d pixel_6
flutter devices
```

Expected: `pixel_api35` appears in `flutter devices` once launched. `x86_64` is required — this is an Intel host and `arm64-v8a` images will not run.

- [ ] **Step 12: Verify the app runs on the simulator**

```bash
flutter run -d DFC5606D-37F0-4176-A73D-B8214C7F820F \
  --dart-define-from-file=config/development.json
```

Expected: default counter app launches. **Demo this on the simulator.**

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "feat: bootstrap Flutter project with flavors and CI

Scaffolds folio for android/ios/windows with bundle dev.folio.app.
Environments via --dart-define-from-file rather than native flavors.
CI runs analyze/test/license-check plus builds on all three platforms
from the first commit, so native-assets breakage surfaces immediately."
```

---

### Task 2: Typed failures and localization

**Files:**
- Create: `lib/core/errors/app_failure.dart`
- Create: `lib/core/errors/failure_messages.dart`
- Create: `lib/l10n/app_en.arb`, `l10n.yaml`
- Modify: `pubspec.yaml` (add `flutter_localizations`, `intl`, enable `generate: true`)
- Test: `test/core/errors/app_failure_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: sealed `AppFailure` with variants `DocumentCorrupt`, `DocumentMoved`, `PermissionRevoked`, `PasswordRequired`, `WrongPassword`, `UnsupportedFeature`, `StorageFull`, `UnknownFailure`; each has `String get code` and `String? get technicalDetail`. `failureMessage(AppFailure, AppLocalizations)` returns the user-facing string.

- [ ] **Step 1: Add localization dependencies**

```bash
cd /Users/user/pdf_suite
flutter pub add flutter_localizations --sdk=flutter
flutter pub add intl:0.20.3
```

Then in `pubspec.yaml` under `flutter:`, add `generate: true`.

`l10n.yaml`:
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

- [ ] **Step 2: Write the failing test**

`test/core/errors/app_failure_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';

void main() {
  group('AppFailure', () {
    test('every variant exposes a stable non-empty code', () {
      const failures = <AppFailure>[
        DocumentCorrupt(),
        DocumentMoved(),
        PermissionRevoked(),
        PasswordRequired(),
        WrongPassword(),
        UnsupportedFeature(),
        StorageFull(),
        UnknownFailure(),
      ];
      for (final f in failures) {
        expect(f.code, isNotEmpty, reason: '${f.runtimeType} has an empty code');
      }
      final codes = failures.map((f) => f.code).toSet();
      expect(codes.length, failures.length, reason: 'codes must be unique');
    });

    test('technical detail is retained for logging but is not the user message', () {
      const f = DocumentCorrupt(technicalDetail: 'xref offset 91827 invalid');
      expect(f.technicalDetail, 'xref offset 91827 invalid');
    });

    test('technical detail defaults to null', () {
      expect(const DocumentMoved().technicalDetail, isNull);
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/errors/app_failure_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Implement the failure hierarchy**

`lib/core/errors/app_failure.dart`:
```dart
/// Typed application failures.
///
/// Raw exceptions never reach the UI (brief section 34). Every failure carries a
/// stable [code] for logging and an optional [technicalDetail] that is logged but
/// never displayed.
sealed class AppFailure {
  const AppFailure({this.technicalDetail});

  final String? technicalDetail;

  String get code;
}

final class DocumentCorrupt extends AppFailure {
  const DocumentCorrupt({super.technicalDetail});
  @override
  String get code => 'document_corrupt';
}

final class DocumentMoved extends AppFailure {
  const DocumentMoved({super.technicalDetail});
  @override
  String get code => 'document_moved';
}

final class PermissionRevoked extends AppFailure {
  const PermissionRevoked({super.technicalDetail});
  @override
  String get code => 'permission_revoked';
}

final class PasswordRequired extends AppFailure {
  const PasswordRequired({super.technicalDetail});
  @override
  String get code => 'password_required';
}

final class WrongPassword extends AppFailure {
  const WrongPassword({super.technicalDetail});
  @override
  String get code => 'wrong_password';
}

final class UnsupportedFeature extends AppFailure {
  const UnsupportedFeature({super.technicalDetail});
  @override
  String get code => 'unsupported_feature';
}

final class StorageFull extends AppFailure {
  const StorageFull({super.technicalDetail});
  @override
  String get code => 'storage_full';
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure({super.technicalDetail});
  @override
  String get code => 'unknown';
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/errors/app_failure_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 6: Write the ARB strings**

`lib/l10n/app_en.arb`:
```json
{
  "@@locale": "en",
  "appTitle": "Folio",
  "errorDocumentCorruptTitle": "Unable to open this PDF.",
  "errorDocumentCorruptBody": "The file may be corrupted or use an unsupported PDF feature.",
  "errorDocumentMovedTitle": "This document has moved.",
  "errorDocumentMovedBody": "It may have been renamed, moved, or deleted outside the app.",
  "errorPermissionRevokedTitle": "No longer able to open this file.",
  "errorPermissionRevokedBody": "Permission to read it was withdrawn. Open it again to restore access.",
  "errorPasswordRequiredTitle": "This PDF is password protected.",
  "errorPasswordRequiredBody": "Enter the password to open it.",
  "errorWrongPasswordTitle": "Incorrect password.",
  "errorWrongPasswordBody": "Check the password and try again.",
  "errorUnsupportedFeatureTitle": "Unable to display this PDF.",
  "errorUnsupportedFeatureBody": "It uses a PDF feature this app does not support yet.",
  "errorStorageFullTitle": "Not enough storage.",
  "errorStorageFullBody": "Free up some space and try again.",
  "errorUnknownTitle": "Something went wrong.",
  "errorUnknownBody": "The operation could not be completed."
}
```

- [ ] **Step 7: Implement the message mapping**

`lib/core/errors/failure_messages.dart`:
```dart
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/l10n/app_localizations.dart';

/// A user-facing description of a failure: a short title and a plain-language body.
///
/// Never includes [AppFailure.technicalDetail] — that goes to the log only.
class FailureMessage {
  const FailureMessage(this.title, this.body);
  final String title;
  final String body;
}

FailureMessage failureMessage(AppFailure failure, AppLocalizations l10n) {
  return switch (failure) {
    DocumentCorrupt() =>
      FailureMessage(l10n.errorDocumentCorruptTitle, l10n.errorDocumentCorruptBody),
    DocumentMoved() =>
      FailureMessage(l10n.errorDocumentMovedTitle, l10n.errorDocumentMovedBody),
    PermissionRevoked() =>
      FailureMessage(l10n.errorPermissionRevokedTitle, l10n.errorPermissionRevokedBody),
    PasswordRequired() =>
      FailureMessage(l10n.errorPasswordRequiredTitle, l10n.errorPasswordRequiredBody),
    WrongPassword() =>
      FailureMessage(l10n.errorWrongPasswordTitle, l10n.errorWrongPasswordBody),
    UnsupportedFeature() =>
      FailureMessage(l10n.errorUnsupportedFeatureTitle, l10n.errorUnsupportedFeatureBody),
    StorageFull() =>
      FailureMessage(l10n.errorStorageFullTitle, l10n.errorStorageFullBody),
    UnknownFailure() =>
      FailureMessage(l10n.errorUnknownTitle, l10n.errorUnknownBody),
  };
}
```

The `switch` is exhaustive over a sealed class, so adding a failure variant without a message becomes a compile error rather than a runtime surprise.

- [ ] **Step 8: Run the full suite and analyzer**

Run: `flutter gen-l10n && flutter analyze && flutter test`
Expected: analyzer clean, all tests pass

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add typed failure hierarchy and localization

Sealed AppFailure with stable codes; exhaustive switch maps each to a
localized title and body. Technical detail is retained for logs and never
shown to users. All strings live in ARB from the first commit."
```

---

### Task 3: Redaction-safe logger

**Files:**
- Create: `lib/core/logging/app_logger.dart`
- Test: `test/core/logging/app_logger_test.dart`

**Interfaces:**
- Consumes: `AppConfig` (Task 1), `AppFailure` (Task 2)
- Produces: `AppLogger` with `void operationStart(String op, {String? fileHash, int? fileSizeBytes})`, `void operationEnd(String op, {required bool success, AppFailure? failure, Duration? elapsed})`, `String hashIdentity(String raw)`, and `List<LogRecord> get buffer`

Brief §38 requires logging operation, timings, size, result, and error code — and forbids logging PDF content, passwords, signatures, or document text. This task makes the forbidden case structurally hard: the logger accepts a hash, never a name or path.

- [ ] **Step 1: Add the logging dependency**

```bash
flutter pub add logging:1.3.0 crypto
```

- [ ] **Step 2: Write the failing test**

`test/core/logging/app_logger_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/logging/app_logger.dart';

void main() {
  late AppLogger logger;

  setUp(() => logger = AppLogger.forTesting());

  group('AppLogger', () {
    test('records an operation with size and result', () {
      logger.operationStart('open_document', fileSizeBytes: 1539);
      logger.operationEnd('open_document',
          success: true, elapsed: const Duration(milliseconds: 9));

      expect(logger.buffer, hasLength(2));
      expect(logger.buffer.last.message, contains('open_document'));
      expect(logger.buffer.last.message, contains('success'));
    });

    test('records the failure code, not the user message', () {
      logger.operationEnd('open_document',
          success: false,
          failure: const DocumentCorrupt(technicalDetail: 'xref offset bad'));

      final line = logger.buffer.last.message;
      expect(line, contains('document_corrupt'));
      expect(line, contains('xref offset bad'));
    });

    test('hashIdentity is stable and does not leak the input', () {
      const path = '/Users/someone/Documents/Salary Slip March.pdf';
      final a = logger.hashIdentity(path);
      final b = logger.hashIdentity(path);

      expect(a, b, reason: 'must be deterministic');
      expect(a, isNot(contains('Salary')));
      expect(a, isNot(contains('someone')));
      expect(a.length, 16, reason: 'truncated hash keeps logs readable');
    });

    test('different inputs hash differently', () {
      expect(logger.hashIdentity('a.pdf'), isNot(logger.hashIdentity('b.pdf')));
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/logging/app_logger_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Implement the logger**

`lib/core/logging/app_logger.dart`:
```dart
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

  factory AppLogger.production() =>
      AppLogger._(Logger('folio'), AppConfig.current.isProduction ? null : <LogRecord>[]);

  final Logger _logger;
  final List<LogRecord>? _captureBuffer;

  List<LogRecord> get buffer => List.unmodifiable(_captureBuffer ?? const []);

  /// A short, stable, non-reversible identifier for a file.
  String hashIdentity(String raw) =>
      sha256.convert(utf8.encode(raw)).toString().substring(0, 16);

  void operationStart(String operation, {String? fileHash, int? fileSizeBytes}) {
    _emit(Level.INFO, _compose('start', operation, {
      if (fileHash != null) 'file': fileHash,
      if (fileSizeBytes != null) 'bytes': '$fileSizeBytes',
    }));
  }

  void operationEnd(
    String operation, {
    required bool success,
    AppFailure? failure,
    Duration? elapsed,
  }) {
    _emit(success ? Level.INFO : Level.WARNING, _compose('end', operation, {
      'result': success ? 'success' : 'failure',
      if (elapsed != null) 'ms': '${elapsed.inMilliseconds}',
      if (failure != null) 'code': failure.code,
      if (failure?.technicalDetail != null) 'detail': failure!.technicalDetail!,
    }));
  }

  String _compose(String phase, String operation, Map<String, String> fields) {
    final parts = ['$phase op=$operation', ...fields.entries.map((e) => '${e.key}=${e.value}')];
    return parts.join(' ');
  }

  void _emit(Level level, String message) {
    final record = LogRecord(level, message, _logger.name);
    _captureBuffer?.add(record);
    _logger.log(level, message);
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/logging/app_logger_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add redaction-safe structured logger

Logs operation, timing, size, result and error code. Takes fileHash rather
than filename so document identity cannot be logged by accident. Production
builds do not retain an in-memory buffer."
```

---

### Task 4: SafeFileWriter — the atomic write pipeline

**Files:**
- Create: `lib/core/storage/app_directories.dart`
- Create: `lib/core/storage/safe_file_writer.dart`
- Test: `test/core/storage/safe_file_writer_test.dart`

**Interfaces:**
- Consumes: `AppFailure` (Task 2)
- Produces: `AppDirectories` with `Future<Directory> libraryRoot()`, `Future<Directory> tempRoot()`; `SafeFileWriter` with `Future<File> write({required File destination, required Future<void> Function(File working) produce, Future<bool> Function(File working)? validate})`

Brief §37: input → temp working file → validate → atomic rename → output. Built now, while nothing writes PDFs, so it is proven before SP-2 depends on it. The temp file must live on the **same volume** as the destination or `rename` degrades to a non-atomic copy.

- [ ] **Step 1: Add path_provider**

```bash
flutter pub add path_provider:2.1.6 path
```

- [ ] **Step 2: Write the failing test**

`test/core/storage/safe_file_writer_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';

void main() {
  late Directory sandbox;
  late SafeFileWriter writer;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('safe_writer_test');
    writer = SafeFileWriter();
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  group('SafeFileWriter', () {
    test('writes the destination file on success', () async {
      final dest = File('${sandbox.path}/out.bin');

      final result = await writer.write(
        destination: dest,
        produce: (working) => working.writeAsBytes([1, 2, 3]),
      );

      expect(result.existsSync(), isTrue);
      expect(await result.readAsBytes(), [1, 2, 3]);
    });

    test('leaves no temp files behind on success', () async {
      final dest = File('${sandbox.path}/out.bin');
      await writer.write(
        destination: dest,
        produce: (working) => working.writeAsBytes([1, 2, 3]),
      );

      final strays = sandbox
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.folio-tmp'));
      expect(strays, isEmpty);
    });

    test('does not create the destination when produce throws', () async {
      final dest = File('${sandbox.path}/never.bin');

      await expectLater(
        writer.write(
          destination: dest,
          produce: (working) async => throw const FileSystemException('disk died'),
        ),
        throwsA(isA<Exception>()),
      );

      expect(dest.existsSync(), isFalse,
          reason: 'a failed write must never leave a partial destination');
    });

    test('cleans up temp files when produce throws', () async {
      final dest = File('${sandbox.path}/never.bin');
      try {
        await writer.write(
          destination: dest,
          produce: (working) async => throw const FileSystemException('disk died'),
        );
      } catch (_) {}

      final strays = sandbox
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.folio-tmp'));
      expect(strays, isEmpty);
    });

    test('rejects the write when validation fails, preserving any existing file', () async {
      final dest = File('${sandbox.path}/existing.bin');
      await dest.writeAsBytes([9, 9, 9]);

      await expectLater(
        writer.write(
          destination: dest,
          produce: (working) => working.writeAsBytes([1, 2, 3]),
          validate: (working) async => false,
        ),
        throwsA(isA<Exception>()),
      );

      expect(await dest.readAsBytes(), [9, 9, 9],
          reason: 'a rejected write must not clobber the original');
    });

    test('places the temp file on the same volume as the destination', () async {
      final dest = File('${sandbox.path}/out.bin');
      String? observedTempDir;

      await writer.write(
        destination: dest,
        produce: (working) async {
          observedTempDir = working.parent.path;
          await working.writeAsBytes([1]);
        },
      );

      expect(observedTempDir, sandbox.path,
          reason: 'cross-volume temp makes rename non-atomic');
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/storage/safe_file_writer_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Implement SafeFileWriter**

`lib/core/storage/safe_file_writer.dart`:
```dart
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
    final working = File('${parent.path}${Platform.pathSeparator}'
        '.folio-tmp-$suffix-${destination.uri.pathSegments.last}');

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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/storage/safe_file_writer_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 6: Implement AppDirectories**

`lib/core/storage/app_directories.dart`:
```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the app-owned directories. The library root holds imported
/// documents; the temp root holds transient working files.
class AppDirectories {
  const AppDirectories();

  Future<Directory> libraryRoot() async {
    final base = await getApplicationSupportDirectory();
    return _ensure(Directory(p.join(base.path, 'library')));
  }

  Future<Directory> tempRoot() async {
    final base = await getApplicationSupportDirectory();
    return _ensure(Directory(p.join(base.path, 'tmp')));
  }

  Future<Directory> _ensure(Directory dir) async {
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
```

`getApplicationSupportDirectory` is used rather than the documents directory so imported copies are not exposed in the user's iOS Files app as app clutter.

- [ ] **Step 7: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: analyzer clean, all tests pass

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add SafeFileWriter atomic write pipeline

Implements brief section 37. Temp file is placed in the destination
directory so rename is atomic; a failed or rejected write never leaves a
partial file and never clobbers an existing destination. Proven by tests
before anything depends on it."
```

---

### Task 5: Theme, breakpoints, and the adaptive shell

**Files:**
- Create: `lib/core/constants/breakpoints.dart`
- Create: `lib/core/theme/app_theme.dart`
- Create: `lib/widgets/adaptive_scaffold.dart`
- Modify: `lib/app.dart`, `lib/main.dart`
- Test: `test/core/breakpoints_test.dart`, `test/widgets/adaptive_scaffold_test.dart`

**Interfaces:**
- Consumes: `AppConfig` (Task 1), `AppLocalizations` (Task 2)
- Produces: `WidthClass` enum (`compact`, `medium`, `expanded`), `WidthClass widthClassFor(double width)`, `AppTheme.light()`, `AppTheme.dark()`, `AdaptiveScaffold({required List<AdaptiveDestination> destinations, required int selectedIndex, required ValueChanged<int> onDestinationSelected, required Widget body})`

- [ ] **Step 1: Write the failing breakpoint test**

`test/core/breakpoints_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/constants/breakpoints.dart';

void main() {
  group('widthClassFor', () {
    test('phone widths are compact', () {
      expect(widthClassFor(320), WidthClass.compact);
      expect(widthClassFor(599.9), WidthClass.compact);
    });

    test('tablet widths are medium', () {
      expect(widthClassFor(600), WidthClass.medium);
      expect(widthClassFor(1024), WidthClass.medium);
    });

    test('desktop widths are expanded', () {
      expect(widthClassFor(1024.1), WidthClass.expanded);
      expect(widthClassFor(1920), WidthClass.expanded);
    });

    test('boundaries are inclusive at the lower bound', () {
      expect(widthClassFor(600), WidthClass.medium);
      expect(widthClassFor(599), WidthClass.compact);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/breakpoints_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement breakpoints**

`lib/core/constants/breakpoints.dart`:
```dart
/// Layout width classes (spec section 7).
///
/// Layout decisions branch on these, never on `Platform.isX`. A Windows window
/// dragged narrow must behave like a phone.
enum WidthClass { compact, medium, expanded }

const double kMediumBreakpoint = 600;
const double kExpandedBreakpoint = 1024;

WidthClass widthClassFor(double width) {
  if (width < kMediumBreakpoint) return WidthClass.compact;
  if (width <= kExpandedBreakpoint) return WidthClass.medium;
  return WidthClass.expanded;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/breakpoints_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 5: Implement the themes**

`lib/core/theme/app_theme.dart`:
```dart
import 'package:flutter/material.dart';

/// Original visual identity. Deliberately not modelled on any commercial PDF
/// product's interface (brief section 9).
abstract final class AppTheme {
  static const Color _seed = Color(0xFF2F5D62);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Accessibility: 48dp minimum touch target (brief section 35).
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
      focusColor: scheme.primary.withValues(alpha: 0.24),
    );
  }
}
```

- [ ] **Step 6: Write the failing adaptive shell test**

`test/widgets/adaptive_scaffold_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/widgets/adaptive_scaffold.dart';

Widget _harness(Size size) => MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: AdaptiveScaffold(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            AdaptiveDestination(icon: Icon(Icons.folder), label: 'Library'),
            AdaptiveDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
          body: const Text('body'),
        ),
      ),
    );

void main() {
  group('AdaptiveScaffold', () {
    testWidgets('compact width uses bottom navigation', (tester) async {
      await tester.pumpWidget(_harness(const Size(400, 800)));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('medium width uses a navigation rail', (tester) async {
      await tester.pumpWidget(_harness(const Size(800, 1000)));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('expanded width uses an extended rail', (tester) async {
      await tester.pumpWidget(_harness(const Size(1400, 900)));
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('body is rendered at every width class', (tester) async {
      for (final size in const [Size(400, 800), Size(800, 1000), Size(1400, 900)]) {
        await tester.pumpWidget(_harness(size));
        expect(find.text('body'), findsOneWidget);
      }
    });
  });
}
```

- [ ] **Step 7: Run to verify it fails**

Run: `flutter test test/widgets/adaptive_scaffold_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 8: Implement AdaptiveScaffold**

`lib/widgets/adaptive_scaffold.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:folio/core/constants/breakpoints.dart';

class AdaptiveDestination {
  const AdaptiveDestination({required this.icon, required this.label});
  final Widget icon;
  final String label;
}

/// Single navigation shell for all platforms. Chooses its layout from the
/// available width, never from the host platform.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final widthClass = widthClassFor(MediaQuery.sizeOf(context).width);

    if (widthClass == WidthClass.compact) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: d.icon, label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: widthClass == WidthClass.expanded,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: widthClass == WidthClass.expanded
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(icon: d.icon, label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: Run to verify it passes**

Run: `flutter test test/widgets/adaptive_scaffold_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 10: Wire the app root**

`lib/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:folio/core/theme/app_theme.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:folio/widgets/adaptive_scaffold.dart';

class FolioApp extends StatefulWidget {
  const FolioApp({super.key});

  @override
  State<FolioApp> createState() => _FolioAppState();
}

class _FolioAppState extends State<FolioApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return AdaptiveScaffold(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              AdaptiveDestination(icon: const Icon(Icons.folder_outlined), label: l10n.appTitle),
              const AdaptiveDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
            ],
            body: Center(child: Text(l10n.appTitle)),
          );
        },
      ),
    );
  }
}
```

`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:folio/app.dart';

void main() {
  runApp(const FolioApp());
}
```

Note: the literal `'Settings'` above is a placeholder that Task 12 replaces with an ARB key when the settings feature lands. Add `settingsLabel` to `app_en.arb` now and use `l10n.settingsLabel` instead if implementing strictly.

- [ ] **Step 11: Verify on the simulator in all three layouts**

```bash
flutter run -d DFC5606D-37F0-4176-A73D-B8214C7F820F \
  --dart-define-from-file=config/development.json
```

Expected: bottom navigation on iPhone. Then run on macOS desktop and resize the window across 600dp and 1024dp to see bar → rail → extended rail. **Demo this on the simulator.**

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "feat: add themes, width-class breakpoints and adaptive shell

Light and dark Material 3 themes with 48dp minimum targets. One
AdaptiveScaffold selects bottom bar, rail, or extended rail from available
width, never from Platform.isX, so a narrow desktop window behaves like a
phone."
```

---

# Stage 2 — Engine abstraction

Ends with: PDFium reachable through an interface that has no write method, plus a fake that lets every later unit test run without a simulator.

---

### Task 6: PdfEngine interface, value types, and the test fake

**Files:**
- Create: `lib/domain/engine/pdf_types.dart`
- Create: `lib/domain/engine/pdf_engine.dart`
- Create: `test/fakes/fake_pdf_engine.dart`
- Test: `test/domain/engine/fake_pdf_engine_test.dart`

**Interfaces:**
- Consumes: `AppFailure` (Task 2)
- Produces:
  - `PdfDocumentHandle` (opaque, `String get id`, `int get pageCount`)
  - `PdfPageInfo({required int index, required double widthPt, required double heightPt, required int rotationQuarterTurns})`
  - `RenderedPage({required int widthPx, required int heightPx, required Uint8List bgraPixels})`
  - `TextRect({required double left, required double top, required double right, required double bottom})`
  - `PageText({required String fullText, required List<TextRect> charRects})`
  - `OutlineNode({required String title, required int? pageIndex, required List<OutlineNode> children})`
  - `DocumentPermissions({required bool allowsCopying, required bool allowsPrinting, required bool allowsDocumentAssembly, required bool allowsModifyAnnotations, required int securityHandlerRevision})`
  - `abstract interface class PdfEngine` — methods `open`, `pageInfo`, `renderPage`, `extractText`, `outline`, `permissions`, `close`
  - `FakePdfEngine` implementing all of the above from in-memory data

**This interface deliberately has no write, save, or export method.** That is what makes "SP-1 cannot alter a PDF" a compile-time property rather than a code-review promise. Do not add one in SP-1.

- [ ] **Step 1: Write the value types**

`lib/domain/engine/pdf_types.dart`:
```dart
import 'dart:typed_data';

/// Opaque handle to an open document. Only the engine that produced it may use it.
class PdfDocumentHandle {
  const PdfDocumentHandle({required this.id, required this.pageCount});
  final String id;
  final int pageCount;
}

class PdfPageInfo {
  const PdfPageInfo({
    required this.index,
    required this.widthPt,
    required this.heightPt,
    required this.rotationQuarterTurns,
  });

  final int index;
  final double widthPt;
  final double heightPt;
  final int rotationQuarterTurns;

  bool get isLandscape => widthPt > heightPt;
}

/// A rasterized page. [bgraPixels] is BGRA8888, matching PDFium's output.
class RenderedPage {
  const RenderedPage({
    required this.widthPx,
    required this.heightPx,
    required this.bgraPixels,
  });

  final int widthPx;
  final int heightPx;
  final Uint8List bgraPixels;
}

/// A rectangle in PDF user space. **The origin is bottom-left and y increases
/// upward**, so [top] is numerically greater than [bottom]. Converting to
/// Flutter's y-down screen space requires flipping against the page height.
class TextRect {
  const TextRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => top - bottom;
}

/// Extracted page text. [charRects] has exactly one entry per code unit in
/// [fullText], so `charRects[i]` locates `fullText[i]`. Search highlighting and
/// selection both rely on this alignment.
class PageText {
  const PageText({required this.fullText, required this.charRects});
  final String fullText;
  final List<TextRect> charRects;

  bool get isEmpty => fullText.isEmpty;
}

class OutlineNode {
  const OutlineNode({
    required this.title,
    required this.pageIndex,
    required this.children,
  });

  final String title;
  final int? pageIndex;
  final List<OutlineNode> children;
}

class DocumentPermissions {
  const DocumentPermissions({
    required this.allowsCopying,
    required this.allowsPrinting,
    required this.allowsDocumentAssembly,
    required this.allowsModifyAnnotations,
    required this.securityHandlerRevision,
  });

  final bool allowsCopying;
  final bool allowsPrinting;
  final bool allowsDocumentAssembly;
  final bool allowsModifyAnnotations;
  final int securityHandlerRevision;
}
```

- [ ] **Step 2: Write the interface**

`lib/domain/engine/pdf_engine.dart`:
```dart
import 'dart:typed_data';

import 'package:folio/domain/engine/pdf_types.dart';

/// Supplies a password when an encrypted document is opened. Returning null
/// cancels the open.
typedef PasswordCallback = Future<String?> Function();

/// Where a document's bytes come from.
sealed class DocumentBytesSource {
  const DocumentBytesSource();
}

final class FileSource extends DocumentBytesSource {
  const FileSource(this.path);
  final String path;
}

final class BytesSource extends DocumentBytesSource {
  const BytesSource(this.bytes, {required this.sourceName});
  final Uint8List bytes;
  final String sourceName;
}

/// Read-only access to PDF documents.
///
/// There is intentionally **no write, save, or export method**. SP-1 ships a
/// reader; document mutation arrives in SP-2 behind a separate interface. Adding
/// a write method here would silently remove the guarantee that SP-1 cannot
/// corrupt a user's file.
///
/// Implementations must throw [AppFailure] subtypes, never raw platform
/// exceptions.
abstract interface class PdfEngine {
  Future<PdfDocumentHandle> open(
    DocumentBytesSource source, {
    PasswordCallback? onPasswordRequired,
  });

  Future<PdfPageInfo> pageInfo(PdfDocumentHandle doc, int pageIndex);

  Future<RenderedPage> renderPage(
    PdfDocumentHandle doc,
    int pageIndex, {
    required int targetWidthPx,
    required int targetHeightPx,
  });

  Future<PageText?> extractText(PdfDocumentHandle doc, int pageIndex);

  Future<List<OutlineNode>> outline(PdfDocumentHandle doc);

  Future<DocumentPermissions?> permissions(PdfDocumentHandle doc);

  Future<void> close(PdfDocumentHandle doc);
}
```

- [ ] **Step 3: Write the failing fake test**

`test/domain/engine/fake_pdf_engine_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';

import '../../fakes/fake_pdf_engine.dart';

void main() {
  group('FakePdfEngine', () {
    test('opens a document and reports its page count', () async {
      final engine = FakePdfEngine()
        ..addDocument('a.pdf', pages: ['Hello world', 'Second page']);

      final doc = await engine.open(const FileSource('a.pdf'));
      expect(doc.pageCount, 2);
    });

    test('extracts text with one rect per character', () async {
      final engine = FakePdfEngine()..addDocument('a.pdf', pages: ['abc']);
      final doc = await engine.open(const FileSource('a.pdf'));

      final text = await engine.extractText(doc, 0);
      expect(text!.fullText, 'abc');
      expect(text.charRects, hasLength(3));
    });

    test('throws DocumentCorrupt for an unknown document', () async {
      final engine = FakePdfEngine();
      await expectLater(
        engine.open(const FileSource('missing.pdf')),
        throwsA(isA<DocumentCorrupt>()),
      );
    });

    test('requests a password for an encrypted document', () async {
      final engine = FakePdfEngine()
        ..addDocument('locked.pdf', pages: ['secret'], password: 'hunter2');

      var asked = false;
      final doc = await engine.open(
        const FileSource('locked.pdf'),
        onPasswordRequired: () async {
          asked = true;
          return 'hunter2';
        },
      );

      expect(asked, isTrue);
      expect(doc.pageCount, 1);
    });

    test('throws WrongPassword when the supplied password is incorrect', () async {
      final engine = FakePdfEngine()
        ..addDocument('locked.pdf', pages: ['secret'], password: 'hunter2');

      await expectLater(
        engine.open(const FileSource('locked.pdf'),
            onPasswordRequired: () async => 'wrong'),
        throwsA(isA<WrongPassword>()),
      );
    });

    test('throws PasswordRequired when the user cancels', () async {
      final engine = FakePdfEngine()
        ..addDocument('locked.pdf', pages: ['secret'], password: 'hunter2');

      await expectLater(
        engine.open(const FileSource('locked.pdf'),
            onPasswordRequired: () async => null),
        throwsA(isA<PasswordRequired>()),
      );
    });

    test('renders a page of the requested pixel size', () async {
      final engine = FakePdfEngine()..addDocument('a.pdf', pages: ['x']);
      final doc = await engine.open(const FileSource('a.pdf'));

      final img = await engine.renderPage(doc, 0, targetWidthPx: 100, targetHeightPx: 141);
      expect(img.widthPx, 100);
      expect(img.heightPx, 141);
      expect(img.bgraPixels, hasLength(100 * 141 * 4));
    });
  });
}
```

- [ ] **Step 4: Run to verify it fails**

Run: `flutter test test/domain/engine/fake_pdf_engine_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 5: Implement the fake**

`test/fakes/fake_pdf_engine.dart`:
```dart
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';

class _FakeDoc {
  _FakeDoc(this.pages, this.password, this.outline);
  final List<String> pages;
  final String? password;
  final List<OutlineNode> outline;
}

/// In-memory [PdfEngine] for unit tests.
///
/// Exists so that domain and data tests run on CI runners with no simulator,
/// which is what makes the 80% coverage target reachable.
class FakePdfEngine implements PdfEngine {
  final Map<String, _FakeDoc> _docs = {};
  final Map<String, String> _openHandles = {};
  int _nextHandle = 0;

  void addDocument(
    String name, {
    required List<String> pages,
    String? password,
    List<OutlineNode> outline = const [],
  }) {
    _docs[name] = _FakeDoc(pages, password, outline);
  }

  String _nameOf(DocumentBytesSource source) => switch (source) {
        FileSource(:final path) => path,
        BytesSource(:final sourceName) => sourceName,
      };

  @override
  Future<PdfDocumentHandle> open(
    DocumentBytesSource source, {
    PasswordCallback? onPasswordRequired,
  }) async {
    final name = _nameOf(source);
    final doc = _docs[name];
    if (doc == null) {
      throw const DocumentCorrupt(technicalDetail: 'fake: no such document');
    }

    if (doc.password != null) {
      final supplied = await onPasswordRequired?.call();
      if (supplied == null) {
        throw const PasswordRequired(technicalDetail: 'fake: open cancelled');
      }
      if (supplied != doc.password) {
        throw const WrongPassword(technicalDetail: 'fake: password mismatch');
      }
    }

    final id = 'fake-${_nextHandle++}';
    _openHandles[id] = name;
    return PdfDocumentHandle(id: id, pageCount: doc.pages.length);
  }

  _FakeDoc _resolve(PdfDocumentHandle handle) {
    final name = _openHandles[handle.id];
    final doc = name == null ? null : _docs[name];
    if (doc == null) {
      throw const UnknownFailure(technicalDetail: 'fake: handle closed or invalid');
    }
    return doc;
  }

  @override
  Future<PdfPageInfo> pageInfo(PdfDocumentHandle doc, int pageIndex) async {
    _resolve(doc);
    return PdfPageInfo(
      index: pageIndex,
      widthPt: 595,
      heightPt: 842,
      rotationQuarterTurns: 0,
    );
  }

  @override
  Future<RenderedPage> renderPage(
    PdfDocumentHandle doc,
    int pageIndex, {
    required int targetWidthPx,
    required int targetHeightPx,
  }) async {
    _resolve(doc);
    return RenderedPage(
      widthPx: targetWidthPx,
      heightPx: targetHeightPx,
      bgraPixels: Uint8List(targetWidthPx * targetHeightPx * 4),
    );
  }

  @override
  Future<PageText?> extractText(PdfDocumentHandle doc, int pageIndex) async {
    final d = _resolve(doc);
    final text = d.pages[pageIndex];
    // One rect per code unit, laid out left to right, mirroring the alignment
    // guarantee documented on PageText.
    return PageText(
      fullText: text,
      charRects: [
        for (var i = 0; i < text.length; i++)
          TextRect(
            left: i * 7.0,
            top: 800,
            right: i * 7.0 + 7,
            bottom: 788,
          ),
      ],
    );
  }

  @override
  Future<List<OutlineNode>> outline(PdfDocumentHandle doc) async =>
      _resolve(doc).outline;

  @override
  Future<DocumentPermissions?> permissions(PdfDocumentHandle doc) async {
    _resolve(doc);
    return const DocumentPermissions(
      allowsCopying: true,
      allowsPrinting: true,
      allowsDocumentAssembly: true,
      allowsModifyAnnotations: true,
      securityHandlerRevision: 0,
    );
  }

  @override
  Future<void> close(PdfDocumentHandle doc) async {
    _openHandles.remove(doc.id);
  }
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/domain/engine/fake_pdf_engine_test.dart`
Expected: PASS — 7 tests

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add PdfEngine interface, value types and test fake

The interface exposes no write method, making read-only a compile-time
property of SP-1. PageText documents the charRects/fullText index alignment
that search and selection depend on, and TextRect documents PDF's y-up
coordinate system. FakePdfEngine lets domain tests run without a simulator."
```

---

### Task 7: PdfrxEngine — the real implementation

**Files:**
- Create: `lib/engine/pdfrx_engine.dart`
- Modify: `pubspec.yaml` (add `pdfrx`), `docs/THIRD_PARTY_LICENSES.md`
- Test: `integration_test/pdfrx_engine_test.dart`

**Interfaces:**
- Consumes: `PdfEngine`, all types from Task 6; `AppFailure` (Task 2)
- Produces: `PdfrxEngine implements PdfEngine`

Tests here are **integration** tests, not unit tests — PDFium is native and needs a simulator or device. This is exactly why Task 6's fake exists.

- [ ] **Step 1: Add pdfrx and record its licence**

```bash
flutter pub add pdfrx:^2.4.7
```

Append to `docs/THIRD_PARTY_LICENSES.md`:
```markdown
## pdfrx 2.4.7
- License: MIT
- Source: https://github.com/espresso3389/pdfrx
- Bundles: PDFium (BSD-3-Clause, Google)
- Redistribution: permitted; attribution retained in this file
- Copyleft obligations: none
```

- [ ] **Step 2: Implement the engine**

`lib/engine/pdfrx_engine.dart`:
```dart
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

/// [PdfEngine] backed by pdfrx / PDFium.
///
/// Translates every pdfrx exception into an [AppFailure] so that raw platform
/// errors never escape the data layer.
class PdfrxEngine implements PdfEngine {
  final Map<String, rx.PdfDocument> _open = {};
  int _nextHandle = 0;

  @override
  Future<PdfDocumentHandle> open(
    DocumentBytesSource source, {
    PasswordCallback? onPasswordRequired,
  }) async {
    var cancelled = false;
    var attempts = 0;

    Future<String?> provider(String _) async {
      attempts++;
      final supplied = await onPasswordRequired?.call();
      if (supplied == null) cancelled = true;
      return supplied;
    }

    try {
      final doc = switch (source) {
        FileSource(:final path) =>
          await rx.PdfDocument.openFile(path, passwordProvider: provider),
        BytesSource(:final bytes, :final sourceName) =>
          await rx.PdfDocument.openData(bytes,
              sourceName: sourceName, passwordProvider: provider),
      };

      final id = 'pdfrx-${_nextHandle++}';
      _open[id] = doc;
      return PdfDocumentHandle(id: id, pageCount: doc.pages.length);
    } on rx.PdfPasswordException catch (e) {
      if (cancelled) {
        throw PasswordRequired(technicalDetail: e.toString());
      }
      // The provider was consulted and still failed, so the password was wrong.
      throw attempts > 0
          ? WrongPassword(technicalDetail: e.toString())
          : PasswordRequired(technicalDetail: e.toString());
    } on rx.PdfException catch (e) {
      throw DocumentCorrupt(technicalDetail: e.toString());
    } catch (e) {
      throw UnknownFailure(technicalDetail: e.toString());
    }
  }

  rx.PdfDocument _resolve(PdfDocumentHandle handle) {
    final doc = _open[handle.id];
    if (doc == null) {
      throw const UnknownFailure(technicalDetail: 'handle closed or invalid');
    }
    return doc;
  }

  @override
  Future<PdfPageInfo> pageInfo(PdfDocumentHandle doc, int pageIndex) async {
    final page = _resolve(doc).pages[pageIndex];
    return PdfPageInfo(
      index: pageIndex,
      widthPt: page.width,
      heightPt: page.height,
      rotationQuarterTurns: page.rotation.index,
    );
  }

  @override
  Future<RenderedPage> renderPage(
    PdfDocumentHandle doc,
    int pageIndex, {
    required int targetWidthPx,
    required int targetHeightPx,
  }) async {
    final page = _resolve(doc).pages[pageIndex];
    final image = await page.render(
      fullWidth: targetWidthPx.toDouble(),
      fullHeight: targetHeightPx.toDouble(),
    );
    if (image == null) {
      throw const UnsupportedFeature(technicalDetail: 'render returned null');
    }
    try {
      return RenderedPage(
        widthPx: image.width,
        heightPx: image.height,
        // Copy before dispose: image.pixels is backed by native memory that
        // becomes invalid the moment dispose() is called.
        bgraPixels: Uint8List.fromList(image.pixels),
      );
    } finally {
      image.dispose();
    }
  }

  @override
  Future<PageText?> extractText(PdfDocumentHandle doc, int pageIndex) async {
    final raw = await _resolve(doc).pages[pageIndex].loadText();
    if (raw == null) return null;
    return PageText(
      fullText: raw.fullText,
      charRects: [
        for (final r in raw.charRects)
          TextRect(left: r.left, top: r.top, right: r.right, bottom: r.bottom),
      ],
    );
  }

  @override
  Future<List<OutlineNode>> outline(PdfDocumentHandle doc) async {
    final nodes = await _resolve(doc).loadOutline();
    return nodes.map(_convertOutline).toList();
  }

  OutlineNode _convertOutline(rx.PdfOutlineNode node) => OutlineNode(
        title: node.title,
        // PdfDest.pageNumber is 1-based; our API is 0-based.
        pageIndex: node.dest?.pageNumber == null ? null : node.dest!.pageNumber - 1,
        children: node.children.map(_convertOutline).toList(),
      );

  @override
  Future<DocumentPermissions?> permissions(PdfDocumentHandle doc) async {
    final p = _resolve(doc).permissions;
    if (p == null) return null;
    return DocumentPermissions(
      allowsCopying: p.allowsCopying,
      allowsPrinting: p.allowsPrinting,
      allowsDocumentAssembly: p.allowsDocumentAssembly,
      allowsModifyAnnotations: p.allowsModifyAnnotations,
      securityHandlerRevision: p.securityHandlerRevision,
    );
  }

  @override
  Future<void> close(PdfDocumentHandle doc) async {
    _open.remove(doc.id)?.dispose();
  }
}
```

Verify `rx.PdfDest.pageNumber` exists and is 1-based before relying on the conversion above; if the field differs, adjust `_convertOutline` and note it in the commit.

- [ ] **Step 3: Write the integration test**

`integration_test/pdfrx_engine_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late PdfrxEngine engine;

  setUp(() => engine = PdfrxEngine());

  group('PdfrxEngine on device', () {
    test('opens the three-page fixture', () async {
      final doc = await engine.open(const FileSource('test_documents/sample_3page.pdf'));
      expect(doc.pageCount, 3);
      await engine.close(doc);
    });

    test('reports page geometry in points', () async {
      final doc = await engine.open(const FileSource('test_documents/sample_3page.pdf'));
      final info = await engine.pageInfo(doc, 0);
      expect(info.widthPt, closeTo(595, 1));
      expect(info.heightPt, closeTo(842, 1));
      await engine.close(doc);
    });

    test('renders BGRA pixels of the requested size', () async {
      final doc = await engine.open(const FileSource('test_documents/sample_3page.pdf'));
      final img = await engine.renderPage(doc, 0, targetWidthPx: 300, targetHeightPx: 424);
      expect(img.widthPx, 300);
      expect(img.bgraPixels.length, img.widthPx * img.heightPx * 4);
      await engine.close(doc);
    });

    test('extracts text with one rect per character', () async {
      final doc = await engine.open(const FileSource('test_documents/sample_3page.pdf'));
      final text = await engine.extractText(doc, 2);
      expect(text, isNotNull);
      expect(text!.fullText, contains('PLATYPUS-TOKEN-42'));
      expect(text.charRects, hasLength(text.fullText.length));
      await engine.close(doc);
    });

    test('surfaces a corrupt file as DocumentCorrupt, not a crash', () async {
      await expectLater(
        engine.open(const FileSource('test_documents/corrupt_truncated.pdf')),
        throwsA(isA<DocumentCorrupt>()),
      );
    });

    test('prompts for a password on an encrypted document', () async {
      var asked = false;
      final doc = await engine.open(
        const FileSource('test_documents/encrypted_user_pw.pdf'),
        onPasswordRequired: () async {
          asked = true;
          return 'folio-test';
        },
      );
      expect(asked, isTrue);
      expect(doc.pageCount, greaterThan(0));
      await engine.close(doc);
    });
  });
}
```

Fixtures referenced here are produced by Task 18. Run that task's generator before this test, or run Task 18 first.

- [ ] **Step 4: Run the integration test on the simulator**

```bash
flutter test integration_test/pdfrx_engine_test.dart \
  -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all tests pass. **Demo this on the simulator.**

- [ ] **Step 5: Push and confirm CI is still green on Windows**

This is the first commit where native assets reach the Windows runner. If `build-windows` fails here, the cause is almost certainly pdfrx's native-assets build under MSVC — investigate before continuing, since every later task builds on this.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: implement PdfrxEngine over PDFium

Maps every pdfrx exception to a typed AppFailure so raw platform errors
never escape the data layer. Copies rendered pixels before disposing the
native image. Converts 1-based PDF outline destinations to 0-based indices.
First commit where native assets reach the Windows CI runner."
```

---

# Stage 3 — Document identity and storage

Ends with: documents importable and reliably reopenable after relaunch on every platform. This is the stage that decides whether Recents works.

---

### Task 8: DocumentRef and library models

**Files:**
- Create: `lib/domain/models/document_ref.dart`
- Create: `lib/domain/models/library_document.dart`
- Test: `test/domain/models/document_ref_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `sealed class DocumentRef`; `ManagedRef({required String relativePath, required String contentHash})`; `ExternalRef({required ExternalHandle handle, required String displayName})`
  - `sealed class ExternalHandle`; `BookmarkHandle(Uint8List data)` (iOS/macOS); `ContentUriHandle(String uri)` (Android); `PathHandle(String path)` (Windows)
  - `DocumentRef.encode()` → `String` and `DocumentRef.decode(String)` for database round-tripping
  - `LibraryDocument({required int id, required DocumentRef ref, required String displayName, required int sizeBytes, required DateTime addedAt, DateTime? lastOpenedAt, required bool isFavorite, int? pageCount})`

- [ ] **Step 1: Write the failing test**

`test/domain/models/document_ref_test.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/models/document_ref.dart';

void main() {
  group('DocumentRef encoding', () {
    test('ManagedRef survives a round trip', () {
      const ref = ManagedRef(relativePath: 'a1b2/invoice.pdf', contentHash: 'deadbeef');
      final decoded = DocumentRef.decode(ref.encode());

      expect(decoded, isA<ManagedRef>());
      final m = decoded as ManagedRef;
      expect(m.relativePath, 'a1b2/invoice.pdf');
      expect(m.contentHash, 'deadbeef');
    });

    test('ExternalRef with a path handle survives a round trip', () {
      const ref = ExternalRef(
        handle: PathHandle(r'C:\Users\a\Documents\x.pdf'),
        displayName: 'x.pdf',
      );
      final decoded = DocumentRef.decode(ref.encode()) as ExternalRef;

      expect(decoded.displayName, 'x.pdf');
      expect((decoded.handle as PathHandle).path, r'C:\Users\a\Documents\x.pdf');
    });

    test('ExternalRef with a bookmark handle preserves the bytes exactly', () {
      final bytes = Uint8List.fromList([0, 1, 2, 250, 255]);
      final ref = ExternalRef(handle: BookmarkHandle(bytes), displayName: 'y.pdf');
      final decoded = DocumentRef.decode(ref.encode()) as ExternalRef;

      expect((decoded.handle as BookmarkHandle).data, bytes);
    });

    test('ExternalRef with a content URI survives a round trip', () {
      const ref = ExternalRef(
        handle: ContentUriHandle('content://com.android.providers/document/1234'),
        displayName: 'z.pdf',
      );
      final decoded = DocumentRef.decode(ref.encode()) as ExternalRef;

      expect((decoded.handle as ContentUriHandle).uri, contains('content://'));
    });

    test('decoding malformed input throws FormatException rather than returning null', () {
      expect(() => DocumentRef.decode('not-json'), throwsA(isA<FormatException>()));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/models/document_ref_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement DocumentRef**

`lib/domain/models/document_ref.dart`:
```dart
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
    final Object? raw;
    try {
      raw = jsonDecode(encoded);
    } on FormatException {
      rethrow;
    }
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/models/document_ref_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 5: Implement LibraryDocument**

`lib/domain/models/library_document.dart`:
```dart
import 'package:folio/domain/models/document_ref.dart';

class LibraryDocument {
  const LibraryDocument({
    required this.id,
    required this.ref,
    required this.displayName,
    required this.sizeBytes,
    required this.addedAt,
    required this.isFavorite,
    this.lastOpenedAt,
    this.pageCount,
  });

  final int id;
  final DocumentRef ref;
  final String displayName;
  final int sizeBytes;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final bool isFavorite;
  final int? pageCount;

  bool get isManaged => ref is ManagedRef;

  LibraryDocument copyWith({
    DateTime? lastOpenedAt,
    bool? isFavorite,
    int? pageCount,
    String? displayName,
  }) =>
      LibraryDocument(
        id: id,
        ref: ref,
        displayName: displayName ?? this.displayName,
        sizeBytes: sizeBytes,
        addedAt: addedAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        isFavorite: isFavorite ?? this.isFavorite,
        pageCount: pageCount ?? this.pageCount,
      );
}
```

- [ ] **Step 6: Commit**

```dart
git add -A
git commit -m "feat: add DocumentRef identity model

Encodes platform-appropriate reopen handles rather than bare paths:
security-scoped bookmarks on iOS, persisted SAF URIs on Android, plain
paths on Windows. Round-trips through JSON for database storage."
```

---

### Task 9: drift database and library DAO

**Files:**
- Create: `lib/data/local/app_database.dart`, `lib/data/local/library_dao.dart`
- Modify: `pubspec.yaml`, `docs/THIRD_PARTY_LICENSES.md`
- Test: `test/data/local/library_dao_test.dart`

**Interfaces:**
- Consumes: `DocumentRef` (Task 8), `LibraryDocument` (Task 8)
- Produces: `AppDatabase` with `AppDatabase.forTesting(QueryExecutor)`; `LibraryDao` with `Future<int> insertDocument(...)`, `Future<List<LibraryDocument>> allDocuments()`, `Future<List<LibraryDocument>> recents({int limit = 20})`, `Future<List<LibraryDocument>> favorites()`, `Future<void> markOpened(int id)`, `Future<void> setFavorite(int id, bool value)`, `Future<void> rename(int id, String name)`, `Future<void> deleteDocument(int id)`

- [ ] **Step 1: Add drift and record licences**

```bash
flutter pub add drift:2.34.3 drift_flutter:0.3.1
flutter pub add --dev drift_dev:2.34.5 build_runner:2.16.0
```

Note: `drift_flutter` pulls `sqlite3` 3.5.2, which builds SQLite through Dart **native assets** (`hooks`, `code_assets`, `native_toolchain_c`). This is the second native-assets dependency after pdfrx. Watch the Windows CI job on the commit that adds it.

Append to `docs/THIRD_PARTY_LICENSES.md`:
```markdown
## drift 2.34.3 / drift_flutter 0.3.1
- License: MIT
- Source: https://github.com/simolus3/drift
- Copyleft obligations: none

## sqlite3 3.5.2 (transitive)
- License: MIT (bindings); SQLite itself is public domain
- Source: https://github.com/simolus3/sqlite3.dart
- Copyleft obligations: none
```

- [ ] **Step 2: Write the failing DAO test**

`test/data/local/library_dao_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/domain/models/document_ref.dart';

void main() {
  late AppDatabase db;
  late LibraryDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = LibraryDao(db);
  });

  tearDown(() => db.close());

  Future<int> insert(String name, {bool favorite = false}) => dao.insertDocument(
        ref: ManagedRef(relativePath: '$name', contentHash: 'hash-$name'),
        displayName: name,
        sizeBytes: 1024,
      );

  group('LibraryDao', () {
    test('inserts and reads back a document', () async {
      final id = await insert('invoice.pdf');
      final all = await dao.allDocuments();

      expect(all, hasLength(1));
      expect(all.single.id, id);
      expect(all.single.displayName, 'invoice.pdf');
      expect(all.single.ref, isA<ManagedRef>());
    });

    test('recents are ordered by most recently opened', () async {
      final a = await insert('a.pdf');
      final b = await insert('b.pdf');

      await dao.markOpened(a);
      await dao.markOpened(b);

      final recents = await dao.recents();
      expect(recents.first.id, b, reason: 'b was opened last');
    });

    test('never-opened documents are excluded from recents', () async {
      await insert('never.pdf');
      expect(await dao.recents(), isEmpty);
    });

    test('favorites returns only favourited documents', () async {
      final a = await insert('a.pdf');
      await insert('b.pdf');
      await dao.setFavorite(a, true);

      final favs = await dao.favorites();
      expect(favs, hasLength(1));
      expect(favs.single.id, a);
    });

    test('rename changes the display name and nothing else', () async {
      final id = await insert('old.pdf');
      await dao.rename(id, 'new.pdf');

      final doc = (await dao.allDocuments()).single;
      expect(doc.displayName, 'new.pdf');
      expect(doc.sizeBytes, 1024);
    });

    test('delete removes the row', () async {
      final id = await insert('gone.pdf');
      await dao.deleteDocument(id);
      expect(await dao.allDocuments(), isEmpty);
    });

    test('recents respects the limit', () async {
      for (var i = 0; i < 5; i++) {
        final id = await insert('doc$i.pdf');
        await dao.markOpened(id);
      }
      expect(await dao.recents(limit: 3), hasLength(3));
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/data/local/library_dao_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Define the schema**

`lib/data/local/app_database.dart`:
```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Serialized DocumentRef (see DocumentRef.encode).
  TextColumn get refPayload => text()();

  TextColumn get displayName => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get pageCount => integer().nullable()();
}

@DriftDatabase(tables: [Documents])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'folio'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}
```

- [ ] **Step 5: Generate the drift code**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `lib/data/local/app_database.g.dart` created.

- [ ] **Step 6: Implement the DAO**

`lib/data/local/library_dao.dart`:
```dart
import 'package:drift/drift.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';

class LibraryDao {
  LibraryDao(this._db);

  final AppDatabase _db;

  Future<int> insertDocument({
    required DocumentRef ref,
    required String displayName,
    required int sizeBytes,
    int? pageCount,
  }) {
    return _db.into(_db.documents).insert(
          DocumentsCompanion.insert(
            refPayload: ref.encode(),
            displayName: displayName,
            sizeBytes: sizeBytes,
            pageCount: Value(pageCount),
          ),
        );
  }

  Future<List<LibraryDocument>> allDocuments() async {
    final rows = await _db.select(_db.documents).get();
    return rows.map(_toDomain).toList();
  }

  Future<List<LibraryDocument>> recents({int limit = 20}) async {
    final query = _db.select(_db.documents)
      ..where((t) => t.lastOpenedAt.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.lastOpenedAt)])
      ..limit(limit);
    return (await query.get()).map(_toDomain).toList();
  }

  Future<List<LibraryDocument>> favorites() async {
    final query = _db.select(_db.documents)..where((t) => t.isFavorite.equals(true));
    return (await query.get()).map(_toDomain).toList();
  }

  Future<void> markOpened(int id) async {
    await (_db.update(_db.documents)..where((t) => t.id.equals(id)))
        .write(DocumentsCompanion(lastOpenedAt: Value(DateTime.now())));
  }

  Future<void> setFavorite(int id, bool value) async {
    await (_db.update(_db.documents)..where((t) => t.id.equals(id)))
        .write(DocumentsCompanion(isFavorite: Value(value)));
  }

  Future<void> rename(int id, String name) async {
    await (_db.update(_db.documents)..where((t) => t.id.equals(id)))
        .write(DocumentsCompanion(displayName: Value(name)));
  }

  Future<void> deleteDocument(int id) async {
    await (_db.delete(_db.documents)..where((t) => t.id.equals(id))).go();
  }

  LibraryDocument _toDomain(Document row) => LibraryDocument(
        id: row.id,
        ref: DocumentRef.decode(row.refPayload),
        displayName: row.displayName,
        sizeBytes: row.sizeBytes,
        addedAt: row.addedAt,
        lastOpenedAt: row.lastOpenedAt,
        isFavorite: row.isFavorite,
        pageCount: row.pageCount,
      );
}
```

- [ ] **Step 7: Run to verify it passes**

Run: `flutter test test/data/local/library_dao_test.dart`
Expected: PASS — 7 tests

`markOpened` uses `DateTime.now()` at second-or-better resolution; if the ordering test proves flaky on fast machines, inject a clock rather than adding a sleep.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add drift database and library DAO

Documents table stores a serialized DocumentRef rather than a path.
Recents excludes never-opened documents. Second native-assets dependency
(sqlite3 3.5.2) — verify the Windows CI job on this commit."
```

---

### Task 10: Platform handles for open-in-place

**Files:**
- Create: `lib/data/file_system/platform_handles.dart`
- Create: `ios/Runner/DocumentHandlePlugin.swift`
- Create: `android/app/src/main/kotlin/dev/folio/app/DocumentHandlePlugin.kt`
- Modify: `ios/Runner/AppDelegate.swift`, `android/app/src/main/kotlin/dev/folio/app/MainActivity.kt`
- Test: `integration_test/platform_handles_test.dart`

**Interfaces:**
- Consumes: `ExternalHandle` (Task 8), `AppFailure` (Task 2)
- Produces: `PlatformHandles` with `Future<ExternalHandle> capture(String pathOrUri)`, `Future<String> resolveToReadablePath(ExternalHandle handle)`, `Future<void> release(ExternalHandle handle)`

**Scope note:** the default import path does **not** need this. `file_selector` returns a temporary copy that Task 11 copies into the library, so `ManagedRef` works with no native code. This task exists only for the secondary open-in-place path that produces `ExternalRef`. If the native work here proves unstable, `ExternalRef` can be dropped from SP-1 and recorded as a limitation without affecting the primary flow — do that rather than shipping a Recents list that fails silently.

- [ ] **Step 1: Write the Dart channel wrapper**

`lib/data/file_system/platform_handles.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/models/document_ref.dart';

/// Captures and resolves durable references to files the app does not own.
class PlatformHandles {
  const PlatformHandles();

  static const MethodChannel _channel = MethodChannel('dev.folio.app/handles');

  /// Converts a freshly picked path or URI into a handle that survives relaunch.
  Future<ExternalHandle> capture(String pathOrUri) async {
    if (Platform.isWindows || Platform.isLinux) {
      return PathHandle(pathOrUri);
    }
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('persistUriPermission', {'uri': pathOrUri});
        return ContentUriHandle(pathOrUri);
      }
      final data = await _channel.invokeMethod<Uint8List>(
        'createBookmark',
        {'path': pathOrUri},
      );
      if (data == null) {
        throw const PermissionRevoked(technicalDetail: 'bookmark creation returned null');
      }
      return BookmarkHandle(data);
    } on PlatformException catch (e) {
      throw PermissionRevoked(technicalDetail: '${e.code}: ${e.message}');
    }
  }

  /// Returns a path the Dart side can read. Callers must call [release] afterwards.
  Future<String> resolveToReadablePath(ExternalHandle handle) async {
    try {
      return switch (handle) {
        PathHandle(:final path) => await _requireExists(path),
        ContentUriHandle(:final uri) => await _invokeString('openContentUri', {'uri': uri}),
        BookmarkHandle(:final data) => await _invokeString('resolveBookmark', {'data': data}),
      };
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'stale' || 'revoked' => PermissionRevoked(technicalDetail: e.message ?? e.code),
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
```

- [ ] **Step 2: Implement the iOS side**

`ios/Runner/DocumentHandlePlugin.swift`:
```swift
import Flutter
import Foundation

/// Security-scoped bookmarks. On iOS a picked URL grants only temporary access;
/// reopening after relaunch requires a bookmark captured at pick time.
public class DocumentHandlePlugin: NSObject, FlutterPlugin {
  private var activeScopes: [String: URL] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.folio.app/handles",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DocumentHandlePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createBookmark":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path missing", details: nil))
        return
      }
      let url = URL(fileURLWithPath: path)
      do {
        let data = try url.bookmarkData(
          options: .minimalBookmark,
          includingResourceValuesForKeys: nil,
          relativeTo: nil)
        result(FlutterStandardTypedData(bytes: data))
      } catch {
        result(FlutterError(code: "bookmark_failed",
                            message: error.localizedDescription, details: nil))
      }

    case "resolveBookmark":
      guard let args = call.arguments as? [String: Any],
            let typed = args["data"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "data missing", details: nil))
        return
      }
      var isStale = false
      do {
        let url = try URL(resolvingBookmarkData: typed.data,
                          options: [],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        if isStale {
          result(FlutterError(code: "stale", message: "bookmark is stale", details: nil))
          return
        }
        guard url.startAccessingSecurityScopedResource() else {
          result(FlutterError(code: "revoked", message: "access denied", details: nil))
          return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
          url.stopAccessingSecurityScopedResource()
          result(FlutterError(code: "missing", message: "file not found", details: nil))
          return
        }
        activeScopes[url.path] = url
        result(url.path)
      } catch {
        result(FlutterError(code: "resolve_failed",
                            message: error.localizedDescription, details: nil))
      }

    case "stopAccessing":
      // Release every scope we opened. Leaving these open leaks kernel resources.
      for (_, url) in activeScopes {
        url.stopAccessingSecurityScopedResource()
      }
      activeScopes.removeAll()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

Register it in `ios/Runner/AppDelegate.swift` inside `application(_:didFinishLaunchingWithOptions:)`, before `GeneratedPluginRegistrant.register(with: self)`:
```swift
DocumentHandlePlugin.register(with: self.registrar(forPlugin: "DocumentHandlePlugin")!)
```

- [ ] **Step 3: Implement the Android side**

`android/app/src/main/kotlin/dev/folio/app/DocumentHandlePlugin.kt`:
```kotlin
package dev.folio.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Storage Access Framework grants are scoped to a single pick. Durable reuse
 * requires takePersistableUriPermission at pick time.
 */
class DocumentHandlePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "persistUriPermission" -> {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
          result.error("bad_args", "uri missing", null); return
        }
        try {
          context.contentResolver.takePersistableUriPermission(
            Uri.parse(uriString),
            Intent.FLAG_GRANT_READ_URI_PERMISSION
          )
          result.success(null)
        } catch (e: SecurityException) {
          result.error("revoked", e.message, null)
        }
      }

      "openContentUri" -> {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
          result.error("bad_args", "uri missing", null); return
        }
        val uri = Uri.parse(uriString)
        val held = context.contentResolver.persistedUriPermissions.any {
          it.uri == uri && it.isReadPermission
        }
        if (!held) {
          result.error("revoked", "no persisted read permission", null); return
        }
        try {
          // Copy into cache so the Dart side gets a plain readable path.
          val cached = File(context.cacheDir, "saf_${uri.hashCode()}.pdf")
          context.contentResolver.openInputStream(uri).use { input ->
            if (input == null) {
              result.error("missing", "cannot open stream", null); return
            }
            cached.outputStream().use { input.copyTo(it) }
          }
          result.success(cached.absolutePath)
        } catch (e: SecurityException) {
          result.error("revoked", e.message, null)
        } catch (e: java.io.FileNotFoundException) {
          result.error("missing", e.message, null)
        }
      }

      else -> result.notImplemented()
    }
  }
}
```

Wire it in `MainActivity.kt`:
```kotlin
package dev.folio.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.folio.app/handles")
      .setMethodCallHandler(DocumentHandlePlugin(applicationContext))
  }
}
```

- [ ] **Step 4: Write the integration test**

`integration_test/platform_handles_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/data/file_system/platform_handles.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const handles = PlatformHandles();

  group('PlatformHandles', () {
    test('captures and resolves a handle for a real file', () async {
      final tmp = File('${Directory.systemTemp.path}/handle_probe.pdf');
      await tmp.writeAsBytes([37, 80, 68, 70]); // %PDF

      final handle = await handles.capture(tmp.path);
      final resolved = await handles.resolveToReadablePath(handle);

      expect(File(resolved).existsSync(), isTrue);
      await handles.release(handle);
      await tmp.delete();
    });

    test('a deleted file resolves to DocumentMoved, not a crash', () async {
      final tmp = File('${Directory.systemTemp.path}/handle_gone.pdf');
      await tmp.writeAsBytes([37, 80, 68, 70]);
      final handle = await handles.capture(tmp.path);
      await tmp.delete();

      await expectLater(
        handles.resolveToReadablePath(handle),
        throwsA(anyOf(isA<DocumentMoved>(), isA<PermissionRevoked>())),
      );
    });
  });
}
```

- [ ] **Step 5: Run on the simulator, then the Android AVD**

```bash
flutter test integration_test/platform_handles_test.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
flutter emulators --launch pixel_api35
flutter test integration_test/platform_handles_test.dart -d emulator-5554
```

Expected: pass on both. **Demo on the simulator.** If iOS bookmark creation fails for files outside a picker grant, that is expected — the test uses a temp file the app already owns; treat a failure here as a signal to test through the real picker instead.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add platform handles for open-in-place documents

iOS security-scoped bookmarks and Android persisted SAF grants, so
externally opened files survive relaunch. Typed failures distinguish a
moved file from a revoked grant. The import path does not depend on this."
```

---

### Task 11: LibraryRepository — import copies in

**Files:**
- Create: `lib/domain/repositories/library_repository.dart`
- Create: `lib/data/file_system/document_resolver.dart`
- Create: `lib/data/repositories/library_repository_impl.dart`
- Modify: `pubspec.yaml` (add `file_selector`)
- Test: `test/data/repositories/library_repository_test.dart`

**Interfaces:**
- Consumes: `LibraryDao` (Task 9), `SafeFileWriter` + `AppDirectories` (Task 4), `DocumentRef` (Task 8), `PlatformHandles` (Task 10), `PdfEngine` (Task 6)
- Produces: `abstract interface class LibraryRepository` with `Future<LibraryDocument> importFile(String sourcePath, {required String displayName})`, `Future<LibraryDocument> openInPlace(String pathOrUri, {required String displayName})`, `Future<List<LibraryDocument>> all()`, `Future<List<LibraryDocument>> recents({int limit = 20})`, `Future<List<LibraryDocument>> favorites()`, `Future<String> resolveReadablePath(LibraryDocument doc)`, `Future<void> markOpened(int id)`, `Future<void> setFavorite(int id, bool value)`, `Future<void> rename(int id, String name)`, `Future<void> delete(int id)`, `Future<LibraryDocument> duplicate(int id)`

- [ ] **Step 1: Add file_selector and record its licence**

```bash
flutter pub add file_selector:1.1.0 crypto
```

Append to `docs/THIRD_PARTY_LICENSES.md`:
```markdown
## file_selector 1.1.0
- License: BSD-3-Clause (Flutter team)
- Source: https://github.com/flutter/packages
- Copyleft obligations: none
```

- [ ] **Step 2: Write the failing test**

`test/data/repositories/library_repository_test.dart`:
```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/models/document_ref.dart';

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late LibraryRepositoryImpl repo;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('library_repo_test');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<File> sourceFile(String name, List<int> bytes) async {
    final f = File('${sandbox.path}/src_$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('LibraryRepositoryImpl.importFile', () {
    test('copies the file into the library and leaves the original untouched', () async {
      final src = await sourceFile('a.pdf', [37, 80, 68, 70, 1, 2, 3]);

      final doc = await repo.importFile(src.path, displayName: 'a.pdf');

      expect(src.existsSync(), isTrue, reason: 'the original must survive');
      expect(doc.ref, isA<ManagedRef>());
      final copied = File(await repo.resolveReadablePath(doc));
      expect(copied.existsSync(), isTrue);
      expect(await copied.readAsBytes(), await src.readAsBytes());
    });

    test('records the size and a content hash', () async {
      final src = await sourceFile('b.pdf', [37, 80, 68, 70, 9]);
      final doc = await repo.importFile(src.path, displayName: 'b.pdf');

      expect(doc.sizeBytes, 5);
      expect((doc.ref as ManagedRef).contentHash, isNotEmpty);
    });

    test('importing the same bytes twice produces the same content hash', () async {
      final a = await sourceFile('c1.pdf', [37, 80, 68, 70, 7]);
      final b = await sourceFile('c2.pdf', [37, 80, 68, 70, 7]);

      final da = await repo.importFile(a.path, displayName: 'c1.pdf');
      final db2 = await repo.importFile(b.path, displayName: 'c2.pdf');

      expect((da.ref as ManagedRef).contentHash, (db2.ref as ManagedRef).contentHash);
    });

    test('rejects a file that is not a PDF', () async {
      final src = await sourceFile('not.pdf', [1, 2, 3, 4]);

      await expectLater(
        repo.importFile(src.path, displayName: 'not.pdf'),
        throwsA(isA<DocumentCorrupt>()),
      );
    });

    test('a missing source yields DocumentMoved', () async {
      await expectLater(
        repo.importFile('${sandbox.path}/nope.pdf', displayName: 'nope.pdf'),
        throwsA(isA<DocumentMoved>()),
      );
    });
  });

  group('LibraryRepositoryImpl lifecycle', () {
    test('delete removes both the row and the managed copy', () async {
      final src = await sourceFile('d.pdf', [37, 80, 68, 70, 5]);
      final doc = await repo.importFile(src.path, displayName: 'd.pdf');
      final path = await repo.resolveReadablePath(doc);

      await repo.delete(doc.id);

      expect(File(path).existsSync(), isFalse);
      expect(await repo.all(), isEmpty);
      expect(src.existsSync(), isTrue, reason: 'the user original is never deleted');
    });

    test('duplicate creates an independent copy', () async {
      final src = await sourceFile('e.pdf', [37, 80, 68, 70, 6]);
      final original = await repo.importFile(src.path, displayName: 'e.pdf');

      final copy = await repo.duplicate(original.id);

      expect(copy.id, isNot(original.id));
      expect(await repo.resolveReadablePath(copy),
          isNot(await repo.resolveReadablePath(original)));
      expect(await repo.all(), hasLength(2));
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/data/repositories/library_repository_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Write the repository interface**

`lib/domain/repositories/library_repository.dart`:
```dart
import 'package:folio/domain/models/library_document.dart';

abstract interface class LibraryRepository {
  Future<LibraryDocument> importFile(String sourcePath, {required String displayName});
  Future<LibraryDocument> openInPlace(String pathOrUri, {required String displayName});
  Future<List<LibraryDocument>> all();
  Future<List<LibraryDocument>> recents({int limit = 20});
  Future<List<LibraryDocument>> favorites();
  Future<String> resolveReadablePath(LibraryDocument doc);
  Future<void> markOpened(int id);
  Future<void> setFavorite(int id, bool value);
  Future<void> rename(int id, String name);
  Future<void> delete(int id);
  Future<LibraryDocument> duplicate(int id);
}
```

- [ ] **Step 5: Implement the repository**

`lib/data/repositories/library_repository_impl.dart`:
```dart
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/file_system/platform_handles.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:path/path.dart' as p;

class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl({
    required LibraryDao dao,
    required SafeFileWriter writer,
    required Directory libraryRoot,
    PlatformHandles handles = const PlatformHandles(),
  })  : _dao = dao,
        _writer = writer,
        _root = libraryRoot,
        _handles = handles;

  final LibraryDao _dao;
  final SafeFileWriter _writer;
  final Directory _root;
  final PlatformHandles _handles;

  /// `%PDF` — checked before import so obviously wrong files are rejected at the
  /// door rather than failing later inside the engine.
  static const List<int> _pdfMagic = [0x25, 0x50, 0x44, 0x46];

  @override
  Future<LibraryDocument> importFile(String sourcePath, {required String displayName}) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const DocumentMoved(technicalDetail: 'source file does not exist');
    }

    final bytes = await source.readAsBytes();
    if (bytes.length < 4 || !_startsWithPdfMagic(bytes)) {
      throw const DocumentCorrupt(technicalDetail: 'missing %PDF header');
    }

    final hash = sha256.convert(bytes).toString();
    final relative = p.join(hash.substring(0, 2), '$hash.pdf');
    final destination = File(p.join(_root.path, relative));

    await _writer.write(
      destination: destination,
      produce: (working) => working.writeAsBytes(bytes, flush: true),
      validate: (working) async => await working.length() == bytes.length,
    );

    final id = await _dao.insertDocument(
      ref: ManagedRef(relativePath: relative, contentHash: hash),
      displayName: displayName,
      sizeBytes: bytes.length,
    );

    return (await all()).firstWhere((d) => d.id == id);
  }

  bool _startsWithPdfMagic(List<int> bytes) {
    for (var i = 0; i < _pdfMagic.length; i++) {
      if (bytes[i] != _pdfMagic[i]) return false;
    }
    return true;
  }

  @override
  Future<LibraryDocument> openInPlace(String pathOrUri, {required String displayName}) async {
    final handle = await _handles.capture(pathOrUri);
    final resolved = await _handles.resolveToReadablePath(handle);
    final size = await File(resolved).length();

    final id = await _dao.insertDocument(
      ref: ExternalRef(handle: handle, displayName: displayName),
      displayName: displayName,
      sizeBytes: size,
    );
    return (await all()).firstWhere((d) => d.id == id);
  }

  @override
  Future<String> resolveReadablePath(LibraryDocument doc) async {
    return switch (doc.ref) {
      ManagedRef(:final relativePath) => _requireManaged(relativePath),
      ExternalRef(:final handle) => await _handles.resolveToReadablePath(handle),
    };
  }

  String _requireManaged(String relativePath) {
    final file = File(p.join(_root.path, relativePath));
    if (!file.existsSync()) {
      throw const DocumentMoved(technicalDetail: 'managed copy is missing');
    }
    return file.path;
  }

  @override
  Future<List<LibraryDocument>> all() => _dao.allDocuments();

  @override
  Future<List<LibraryDocument>> recents({int limit = 20}) => _dao.recents(limit: limit);

  @override
  Future<List<LibraryDocument>> favorites() => _dao.favorites();

  @override
  Future<void> markOpened(int id) => _dao.markOpened(id);

  @override
  Future<void> setFavorite(int id, bool value) => _dao.setFavorite(id, value);

  @override
  Future<void> rename(int id, String name) => _dao.rename(id, name);

  @override
  Future<void> delete(int id) async {
    final doc = (await all()).firstWhere((d) => d.id == id);
    // Only ever delete a copy the app made. A user's own file is never removed.
    if (doc.ref case ManagedRef(:final relativePath)) {
      final file = File(p.join(_root.path, relativePath));
      if (file.existsSync()) await file.delete();
    }
    await _dao.deleteDocument(id);
  }

  @override
  Future<LibraryDocument> duplicate(int id) async {
    final doc = (await all()).firstWhere((d) => d.id == id);
    final sourcePath = await resolveReadablePath(doc);
    final bytes = await File(sourcePath).readAsBytes();

    // Salt the hash so the duplicate is a distinct managed file rather than
    // collapsing onto the original's content-addressed path.
    final salted = sha256.convert([...bytes, ...DateTime.now().toIso8601String().codeUnits]).toString();
    final relative = p.join(salted.substring(0, 2), '$salted.pdf');

    await _writer.write(
      destination: File(p.join(_root.path, relative)),
      produce: (working) => working.writeAsBytes(bytes, flush: true),
    );

    final newId = await _dao.insertDocument(
      ref: ManagedRef(relativePath: relative, contentHash: salted),
      displayName: '${doc.displayName} copy',
      sizeBytes: bytes.length,
    );
    return (await all()).firstWhere((d) => d.id == newId);
  }
}
```

Note the content-addressed layout: importing identical bytes twice reuses the same managed file, which is why `duplicate` salts its hash deliberately.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/data/repositories/library_repository_test.dart`
Expected: PASS — 7 tests

- [ ] **Step 7: Run the whole suite and check coverage**

```bash
flutter analyze && flutter test --coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
```

Expected: analyzer clean; `lib/domain` and `lib/data` at or above 80%.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add LibraryRepository with import-copies-in

Imports validate the %PDF header, copy through SafeFileWriter, and store a
content-addressed ManagedRef. Delete removes only app-owned copies, never a
user's original. Duplicate salts its hash to avoid collapsing onto the
content-addressed path of the source."
```

---

# Stage 4 — Features

Ends with: a usable reader. Demo on the simulator after every task in this stage.

**Deliberate architectural exception:** the viewer feature uses pdfrx's `PdfViewer`
widget directly rather than routing rendering through `PdfEngine`. `PdfViewer` is a
UI component with its own tile cache, scroll physics, and bitmap lifecycle —
reimplementing that over `renderPage` would be worse code and worse performance.
`PdfEngine` remains the only path for **headless** work (text, outline, permissions,
thumbnails), which is what unit tests exercise. Record this in `docs/ARCHITECTURE.md`.

---

### Task 12: Providers and the library screen

**Files:**
- Create: `lib/features/home/providers.dart`, `lib/features/home/library_screen.dart`, `lib/features/home/widgets/document_tile.dart`, `lib/features/home/widgets/empty_library.dart`
- Modify: `lib/main.dart`, `lib/app.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/home/library_controller_test.dart`

**Interfaces:**
- Consumes: `LibraryRepository` (Task 11), `AdaptiveScaffold` (Task 5), `failureMessage` (Task 2)
- Produces: `libraryRepositoryProvider`, `libraryControllerProvider` (an `AsyncNotifier<List<LibraryDocument>>` exposing `importFromPicker()`, `refresh()`, `toggleFavorite(int)`, `remove(int)`, `renameDocument(int, String)`)

- [ ] **Step 1: Add riverpod**

```bash
flutter pub add flutter_riverpod:3.4.2
```

Append to `docs/THIRD_PARTY_LICENSES.md`:
```markdown
## flutter_riverpod 3.4.2
- License: MIT
- Source: https://github.com/rrousselGit/riverpod
- Copyleft obligations: none
```

- [ ] **Step 2: Add the ARB strings**

Add to `lib/l10n/app_en.arb`:
```json
{
  "libraryTitle": "Library",
  "settingsLabel": "Settings",
  "emptyLibraryTitle": "No documents yet",
  "emptyLibraryBody": "Import a PDF to get started. Files are copied into the app so they always reopen.",
  "importAction": "Import PDF",
  "openInPlaceAction": "Open without importing",
  "favoriteAction": "Favorite",
  "renameAction": "Rename",
  "deleteAction": "Delete",
  "duplicateAction": "Duplicate",
  "recentsTitle": "Recent",
  "favoritesTitle": "Favorites",
  "searchHint": "Search documents",
  "sortByName": "Name",
  "sortByDateAdded": "Date added",
  "sortByDateOpened": "Last opened",
  "sortBySize": "Size",
  "importedCopyBadge": "Imported copy",
  "unavailableBadge": "Unavailable",
  "locateAgainAction": "Locate again",
  "pageCountLabel": "{count} pages",
  "@pageCountLabel": {
    "placeholders": { "count": { "type": "int" } }
  }
}
```

- [ ] **Step 3: Write the failing controller test**

`test/features/home/library_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/features/home/providers.dart';

class _FakeRepo implements LibraryRepository {
  final List<LibraryDocument> docs = [];
  int _nextId = 1;

  LibraryDocument _make(String name, {bool favorite = false}) => LibraryDocument(
        id: _nextId++,
        ref: ManagedRef(relativePath: name, contentHash: name),
        displayName: name,
        sizeBytes: 100,
        addedAt: DateTime(2026, 8, 24),
        isFavorite: favorite,
      );

  void seed(String name) => docs.add(_make(name));

  @override
  Future<List<LibraryDocument>> all() async => List.of(docs);

  @override
  Future<void> setFavorite(int id, bool value) async {
    final i = docs.indexWhere((d) => d.id == id);
    docs[i] = docs[i].copyWith(isFavorite: value);
  }

  @override
  Future<void> delete(int id) async => docs.removeWhere((d) => d.id == id);

  @override
  Future<void> rename(int id, String name) async {
    final i = docs.indexWhere((d) => d.id == id);
    docs[i] = docs[i].copyWith(displayName: name);
  }

  @override
  Future<LibraryDocument> importFile(String sourcePath, {required String displayName}) async {
    final doc = _make(displayName);
    docs.add(doc);
    return doc;
  }

  @override
  Future<List<LibraryDocument>> favorites() async =>
      docs.where((d) => d.isFavorite).toList();

  @override
  Future<List<LibraryDocument>> recents({int limit = 20}) async =>
      docs.where((d) => d.lastOpenedAt != null).toList();

  @override
  Future<void> markOpened(int id) async {}

  @override
  Future<String> resolveReadablePath(LibraryDocument doc) async => doc.displayName;

  @override
  Future<LibraryDocument> openInPlace(String pathOrUri, {required String displayName}) async =>
      _make(displayName);

  @override
  Future<LibraryDocument> duplicate(int id) async {
    final doc = _make('copy');
    docs.add(doc);
    return doc;
  }
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo();
    container = ProviderContainer(
      overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() => container.dispose());

  group('LibraryController', () {
    test('loads documents from the repository', () async {
      repo..seed('a.pdf')..seed('b.pdf');
      final docs = await container.read(libraryControllerProvider.future);
      expect(docs, hasLength(2));
    });

    test('toggleFavorite updates the document', () async {
      repo.seed('a.pdf');
      await container.read(libraryControllerProvider.future);

      await container.read(libraryControllerProvider.notifier).toggleFavorite(1);
      final docs = await container.read(libraryControllerProvider.future);

      expect(docs.single.isFavorite, isTrue);
    });

    test('remove deletes the document', () async {
      repo.seed('a.pdf');
      await container.read(libraryControllerProvider.future);

      await container.read(libraryControllerProvider.notifier).remove(1);
      final docs = await container.read(libraryControllerProvider.future);

      expect(docs, isEmpty);
    });

    test('renameDocument changes the display name', () async {
      repo.seed('old.pdf');
      await container.read(libraryControllerProvider.future);

      await container.read(libraryControllerProvider.notifier).renameDocument(1, 'new.pdf');
      final docs = await container.read(libraryControllerProvider.future);

      expect(docs.single.displayName, 'new.pdf');
    });
  });
}
```

- [ ] **Step 4: Run to verify it fails**

Run: `flutter test test/features/home/library_controller_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 5: Implement the providers**

`lib/features/home/providers.dart`:
```dart
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';

/// Overridden at app start with the real implementation, and in tests with a fake.
final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => throw UnimplementedError('libraryRepositoryProvider must be overridden'),
);

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, List<LibraryDocument>>(
  LibraryController.new,
);

class LibraryController extends AsyncNotifier<List<LibraryDocument>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  Future<List<LibraryDocument>> build() => _repo.all();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.all);
  }

  Future<void> importFromPicker() async {
    const typeGroup = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
      mimeTypes: ['application/pdf'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    state = await AsyncValue.guard(() async {
      await _repo.importFile(file.path, displayName: file.name);
      return _repo.all();
    });
  }

  Future<void> toggleFavorite(int id) async {
    final current = state.valueOrNull ?? const [];
    final doc = current.firstWhere((d) => d.id == id);
    state = await AsyncValue.guard(() async {
      await _repo.setFavorite(id, !doc.isFavorite);
      return _repo.all();
    });
  }

  Future<void> remove(int id) async {
    state = await AsyncValue.guard(() async {
      await _repo.delete(id);
      return _repo.all();
    });
  }

  Future<void> renameDocument(int id, String name) async {
    state = await AsyncValue.guard(() async {
      await _repo.rename(id, name);
      return _repo.all();
    });
  }
}
```

The `uniformTypeIdentifiers: ['com.adobe.pdf']` entry is Apple's registered UTI for the PDF **format**, which is an open ISO standard (ISO 32000). Declaring it is required for the iOS picker to show PDFs and carries no dependency on Adobe software.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/features/home/library_controller_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 7: Build the library screen**

`lib/features/home/library_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/errors/failure_messages.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/home/widgets/document_tile.dart';
import 'package:folio/features/home/widgets/empty_library.dart';
import 'package:folio/l10n/app_localizations.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final docs = ref.watch(libraryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            ref.read(libraryControllerProvider.notifier).importFromPicker(),
        icon: const Icon(Icons.add),
        label: Text(l10n.importAction),
      ),
      body: docs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final failure = error is AppFailure ? error : const UnknownFailure();
          final message = failureMessage(failure, l10n);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(message.body, textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        },
        data: (items) {
          if (items.isEmpty) return const EmptyLibrary();
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => DocumentTile(document: items[i]),
          );
        },
      ),
    );
  }
}
```

`lib/features/home/widgets/empty_library.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(l10n.emptyLibraryTitle,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.emptyLibraryBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
```

`lib/features/home/widgets/document_tile.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/l10n/app_localizations.dart';

class DocumentTile extends ConsumerWidget {
  const DocumentTile({super.key, required this.document});

  final LibraryDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sizeKb = (document.sizeBytes / 1024).toStringAsFixed(0);

    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(document.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          '$sizeKb KB',
          if (document.pageCount != null) l10n.pageCountLabel(document.pageCount!),
          if (document.isManaged) l10n.importedCopyBadge,
        ].join(' · '),
      ),
      trailing: IconButton(
        icon: Icon(document.isFavorite ? Icons.star : Icons.star_border),
        tooltip: l10n.favoriteAction,
        onPressed: () =>
            ref.read(libraryControllerProvider.notifier).toggleFavorite(document.id),
      ),
      onTap: () {
        // Viewer navigation is wired in Task 14.
      },
    );
  }
}
```

- [ ] **Step 8: Wire the app root**

`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/app.dart';
import 'package:folio/core/storage/app_directories.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/features/home/providers.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  const dirs = AppDirectories();
  final libraryRoot = await dirs.libraryRoot();
  final db = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(
          LibraryRepositoryImpl(
            dao: LibraryDao(db),
            writer: SafeFileWriter(),
            libraryRoot: libraryRoot,
          ),
        ),
      ],
      child: const FolioApp(),
    ),
  );
}
```

Update `lib/app.dart` so the first destination renders `const LibraryScreen()` instead of the placeholder `Center`.

- [ ] **Step 9: Verify on the simulator**

```bash
flutter run -d DFC5606D-37F0-4176-A73D-B8214C7F820F \
  --dart-define-from-file=config/development.json
```

Expected: empty-library state, then tap Import, pick a PDF, and see it listed. **Demo this on the simulator.**

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: add library screen with import

Riverpod controller over LibraryRepository; picker filters to PDF by
extension, MIME type and UTI. Failures render as localized title and body,
never as a stack trace."
```

---

### Task 13: Recents, favorites, search and sort

**Files:**
- Create: `lib/domain/services/document_sorter.dart`, `lib/features/home/widgets/library_toolbar.dart`
- Modify: `lib/features/home/providers.dart`, `lib/features/home/library_screen.dart`
- Test: `test/domain/services/document_sorter_test.dart`

**Interfaces:**
- Consumes: `LibraryDocument` (Task 8), `libraryControllerProvider` (Task 12)
- Produces: `enum SortField { name, dateAdded, dateOpened, size }`; `List<LibraryDocument> sortDocuments(List<LibraryDocument>, {required SortField field, required bool ascending})`; `List<LibraryDocument> filterDocuments(List<LibraryDocument>, String query)`; providers `sortFieldProvider`, `sortAscendingProvider`, `searchQueryProvider`, `visibleDocumentsProvider`

- [ ] **Step 1: Write the failing test**

`test/domain/services/document_sorter_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/services/document_sorter.dart';

LibraryDocument doc(
  String name, {
  int size = 100,
  DateTime? added,
  DateTime? opened,
}) =>
    LibraryDocument(
      id: name.hashCode,
      ref: ManagedRef(relativePath: name, contentHash: name),
      displayName: name,
      sizeBytes: size,
      addedAt: added ?? DateTime(2026),
      lastOpenedAt: opened,
      isFavorite: false,
    );

void main() {
  group('sortDocuments', () {
    test('sorts by name case-insensitively', () {
      final result = sortDocuments(
        [doc('banana.pdf'), doc('Apple.pdf'), doc('cherry.pdf')],
        field: SortField.name,
        ascending: true,
      );
      expect(result.map((d) => d.displayName), ['Apple.pdf', 'banana.pdf', 'cherry.pdf']);
    });

    test('reverses when ascending is false', () {
      final result = sortDocuments(
        [doc('a.pdf'), doc('b.pdf')],
        field: SortField.name,
        ascending: false,
      );
      expect(result.first.displayName, 'b.pdf');
    });

    test('sorts by size', () {
      final result = sortDocuments(
        [doc('big.pdf', size: 900), doc('small.pdf', size: 10)],
        field: SortField.size,
        ascending: true,
      );
      expect(result.first.displayName, 'small.pdf');
    });

    test('never-opened documents sort last when sorting by last opened', () {
      final result = sortDocuments(
        [doc('never.pdf'), doc('opened.pdf', opened: DateTime(2026, 5, 1))],
        field: SortField.dateOpened,
        ascending: false,
      );
      expect(result.first.displayName, 'opened.pdf');
      expect(result.last.displayName, 'never.pdf');
    });

    test('does not mutate the input list', () {
      final input = [doc('b.pdf'), doc('a.pdf')];
      sortDocuments(input, field: SortField.name, ascending: true);
      expect(input.first.displayName, 'b.pdf');
    });
  });

  group('filterDocuments', () {
    test('matches case-insensitively on a substring', () {
      final result = filterDocuments([doc('Invoice March.pdf'), doc('notes.pdf')], 'invoice');
      expect(result, hasLength(1));
    });

    test('an empty query returns everything', () {
      final all = [doc('a.pdf'), doc('b.pdf')];
      expect(filterDocuments(all, ''), hasLength(2));
    });

    test('a whitespace-only query returns everything', () {
      final all = [doc('a.pdf'), doc('b.pdf')];
      expect(filterDocuments(all, '   '), hasLength(2));
    });

    test('no match returns empty', () {
      expect(filterDocuments([doc('a.pdf')], 'zzz'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/services/document_sorter_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement the sorter**

`lib/domain/services/document_sorter.dart`:
```dart
import 'package:folio/domain/models/library_document.dart';

enum SortField { name, dateAdded, dateOpened, size }

/// Pure sorting. Returns a new list; the input is never mutated.
List<LibraryDocument> sortDocuments(
  List<LibraryDocument> documents, {
  required SortField field,
  required bool ascending,
}) {
  final copy = List<LibraryDocument>.of(documents);

  copy.sort((a, b) {
    final result = switch (field) {
      SortField.name =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      SortField.dateAdded => a.addedAt.compareTo(b.addedAt),
      SortField.size => a.sizeBytes.compareTo(b.sizeBytes),
      SortField.dateOpened => _compareNullableDates(a.lastOpenedAt, b.lastOpenedAt),
    };
    return ascending ? result : -result;
  });

  return copy;
}

/// Never-opened documents sort as oldest, so that with `ascending: false`
/// (most recent first) they land at the end rather than the top.
int _compareNullableDates(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return a.compareTo(b);
}

List<LibraryDocument> filterDocuments(List<LibraryDocument> documents, String query) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return documents;
  return documents
      .where((d) => d.displayName.toLowerCase().contains(trimmed))
      .toList();
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/services/document_sorter_test.dart`
Expected: PASS — 9 tests

- [ ] **Step 5: Add the view-state providers**

Append to `lib/features/home/providers.dart`:
```dart
final sortFieldProvider = StateProvider<SortField>((ref) => SortField.dateAdded);
final sortAscendingProvider = StateProvider<bool>((ref) => false);
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Documents after filtering and sorting, ready for the list to render.
final visibleDocumentsProvider = Provider<AsyncValue<List<LibraryDocument>>>((ref) {
  final docs = ref.watch(libraryControllerProvider);
  final query = ref.watch(searchQueryProvider);
  final field = ref.watch(sortFieldProvider);
  final ascending = ref.watch(sortAscendingProvider);

  return docs.whenData(
    (items) => sortDocuments(
      filterDocuments(items, query),
      field: field,
      ascending: ascending,
    ),
  );
});
```

Add the imports for `document_sorter.dart` at the top of the file.

- [ ] **Step 6: Add the toolbar and tab sections**

`lib/features/home/widgets/library_toolbar.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/services/document_sorter.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/l10n/app_localizations.dart';

class LibraryToolbar extends ConsumerWidget {
  const LibraryToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    String labelFor(SortField f) => switch (f) {
          SortField.name => l10n.sortByName,
          SortField.dateAdded => l10n.sortByDateAdded,
          SortField.dateOpened => l10n.sortByDateOpened,
          SortField.size => l10n.sortBySize,
        };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => ref.read(searchQueryProvider.notifier).state = v,
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<SortField>(
            icon: const Icon(Icons.sort),
            tooltip: l10n.sortByName,
            onSelected: (f) => ref.read(sortFieldProvider.notifier).state = f,
            itemBuilder: (context) => [
              for (final f in SortField.values)
                PopupMenuItem(value: f, child: Text(labelFor(f))),
            ],
          ),
          IconButton(
            tooltip: l10n.sortByName,
            icon: Icon(ref.watch(sortAscendingProvider)
                ? Icons.arrow_upward
                : Icons.arrow_downward),
            onPressed: () => ref.read(sortAscendingProvider.notifier).state =
                !ref.read(sortAscendingProvider),
          ),
        ],
      ),
    );
  }
}
```

Update `LibraryScreen` to watch `visibleDocumentsProvider` instead of `libraryControllerProvider`, place `LibraryToolbar` above the list, and add a `TabBar` with three tabs — all documents, `l10n.recentsTitle`, `l10n.favoritesTitle` — each rendering a filtered view of the same list.

- [ ] **Step 7: Verify on the simulator**

Import several PDFs, type in the search box, change sort field and direction, star a document, and check the Favorites tab. **Demo this on the simulator.**

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add search, sort, recents and favorites

Pure sort and filter functions with never-opened documents ordered last.
View state lives in providers so the list rebuilds without refetching."
```

---

### Task 13b: Collections, move, and Save As

**Files:**
- Modify: `lib/data/local/app_database.dart` (schema v2), `lib/data/local/library_dao.dart`, `lib/domain/repositories/library_repository.dart`, `lib/data/repositories/library_repository_impl.dart`, `lib/features/home/library_screen.dart`, `lib/l10n/app_en.arb`
- Create: `lib/features/home/widgets/collection_bar.dart`
- Test: `test/data/local/collections_dao_test.dart`

**Interfaces:**
- Consumes: `LibraryDao` (Task 9), `LibraryRepository` (Task 11), `SafeFileWriter` (Task 4)
- Produces: `Collections` table; `LibraryDao.createCollection(String name)`, `.renameCollection(int, String)`, `.deleteCollection(int)`, `.allCollections()`, `.moveDocument(int docId, int? collectionId)`, `.documentsIn(int? collectionId)`; `LibraryRepository.moveToCollection(int docId, int? collectionId)`, `.exportCopy(int docId, String destinationPath)`

Covers the three spec §8 F1 capabilities not yet built: **folder navigation**, **move**, and **Save As**.

Managed files are stored content-addressed and flat on disk, so folders are **virtual** — a `collectionId` on the document row, not a directory. This keeps deduplication working and makes move an `UPDATE` rather than a file operation that could fail halfway.

- [ ] **Step 1: Write the failing DAO test**

`test/data/local/collections_dao_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/domain/models/document_ref.dart';

void main() {
  late AppDatabase db;
  late LibraryDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = LibraryDao(db);
  });

  tearDown(() => db.close());

  Future<int> insert(String name) => dao.insertDocument(
        ref: ManagedRef(relativePath: name, contentHash: name),
        displayName: name,
        sizeBytes: 10,
      );

  group('collections', () {
    test('a new document belongs to no collection', () async {
      await insert('a.pdf');
      final loose = await dao.documentsIn(null);
      expect(loose, hasLength(1));
    });

    test('moving a document places it in the collection', () async {
      final doc = await insert('a.pdf');
      final folder = await dao.createCollection('Invoices');

      await dao.moveDocument(doc, folder);

      expect(await dao.documentsIn(folder), hasLength(1));
      expect(await dao.documentsIn(null), isEmpty);
    });

    test('moving to null returns a document to the root', () async {
      final doc = await insert('a.pdf');
      final folder = await dao.createCollection('Invoices');
      await dao.moveDocument(doc, folder);

      await dao.moveDocument(doc, null);

      expect(await dao.documentsIn(null), hasLength(1));
    });

    test('deleting a collection returns its documents to the root, never deleting them', () async {
      final doc = await insert('a.pdf');
      final folder = await dao.createCollection('Invoices');
      await dao.moveDocument(doc, folder);

      await dao.deleteCollection(folder);

      expect(await dao.allCollections(), isEmpty);
      expect(await dao.documentsIn(null), hasLength(1),
          reason: 'deleting a folder must never delete documents');
    });

    test('renaming a collection preserves its membership', () async {
      final doc = await insert('a.pdf');
      final folder = await dao.createCollection('Old');
      await dao.moveDocument(doc, folder);

      await dao.renameCollection(folder, 'New');

      expect((await dao.allCollections()).single.name, 'New');
      expect(await dao.documentsIn(folder), hasLength(1));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/local/collections_dao_test.dart`
Expected: FAIL — `createCollection` is not defined

- [ ] **Step 3: Migrate the schema to version 2**

In `lib/data/local/app_database.dart`, add the table and a nullable foreign key, then bump the version:

```dart
class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

Add to `Documents`:
```dart
  /// Null means the document sits at the library root.
  IntColumn get collectionId =>
      integer().nullable().references(Collections, #id, onDelete: KeyAction.setNull)();
```

Update the annotation to `@DriftDatabase(tables: [Documents, Collections])`, set `schemaVersion => 2`, and add the migration:

```dart
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(collections);
            await m.addColumn(documents, documents.collectionId);
          }
        },
      );
```

`onDelete: KeyAction.setNull` is what guarantees the fourth test: deleting a folder can never cascade into deleting documents.

Regenerate: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 4: Implement the DAO methods**

Add to `LibraryDao`:
```dart
  Future<int> createCollection(String name) =>
      _db.into(_db.collections).insert(CollectionsCompanion.insert(name: name));

  Future<void> renameCollection(int id, String name) async {
    await (_db.update(_db.collections)..where((t) => t.id.equals(id)))
        .write(CollectionsCompanion(name: Value(name)));
  }

  Future<void> deleteCollection(int id) async {
    await (_db.delete(_db.collections)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Collection>> allCollections() => _db.select(_db.collections).get();

  Future<void> moveDocument(int docId, int? collectionId) async {
    await (_db.update(_db.documents)..where((t) => t.id.equals(docId)))
        .write(DocumentsCompanion(collectionId: Value(collectionId)));
  }

  Future<List<LibraryDocument>> documentsIn(int? collectionId) async {
    final query = _db.select(_db.documents)
      ..where((t) => collectionId == null
          ? t.collectionId.isNull()
          : t.collectionId.equals(collectionId));
    return (await query.get()).map(_toDomain).toList();
  }
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/data/local/collections_dao_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 6: Implement Save As on the repository**

Add to `LibraryRepository` and its implementation:
```dart
  /// Copies a managed document out to a user-chosen location.
  ///
  /// The library copy is left untouched — Save As exports, it does not move.
  @override
  Future<void> exportCopy(int docId, String destinationPath) async {
    final doc = (await all()).firstWhere((d) => d.id == docId);
    final bytes = await File(await resolveReadablePath(doc)).readAsBytes();

    await _writer.write(
      destination: File(destinationPath),
      produce: (working) => working.writeAsBytes(bytes, flush: true),
      validate: (working) async => await working.length() == bytes.length,
    );
  }

  @override
  Future<void> moveToCollection(int docId, int? collectionId) =>
      _dao.moveDocument(docId, collectionId);
```

Wire the UI action using `file_selector`'s save dialog:
```dart
final location = await getSaveLocation(suggestedName: document.displayName);
if (location != null) {
  await repo.exportCopy(document.id, location.path);
}
```

- [ ] **Step 7: Add the collection bar to the library screen**

`lib/features/home/widgets/collection_bar.dart` renders a horizontal chip row: an "All" chip plus one per collection, with a trailing chip to create one. Selecting a chip sets `selectedCollectionProvider`, which `visibleDocumentsProvider` reads to filter. Long-press a document to move it, via a menu listing the collections plus "Library root".

Add ARB strings: `collectionsAll`, `collectionNew`, `collectionNameHint`, `moveToAction`, `moveToRoot`, `saveAsAction`, `exportSuccess`.

- [ ] **Step 8: Verify on the simulator**

Create a collection, move a document into it, filter by chip, rename the collection, delete it and confirm the documents return to the root rather than vanishing. Use Save As and confirm the exported file opens while the library copy remains. **Demo this on the simulator.**

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add collections, move and Save As

Folders are virtual — a nullable collectionId on the document row — so
content-addressed deduplication keeps working and move is an UPDATE rather
than a file operation. Deleting a collection sets the key null, so it can
never cascade into deleting documents. Save As exports a copy and leaves
the library untouched."
```

---

### Task 14: Viewer core, zoom, navigation and the password flow

**Files:**
- Create: `lib/features/viewer/viewer_screen.dart`, `lib/features/viewer/providers.dart`, `lib/features/viewer/widgets/password_prompt.dart`
- Modify: `lib/features/home/widgets/document_tile.dart` (wire `onTap`), `lib/l10n/app_en.arb`
- Test: `integration_test/viewer_open_test.dart`

**Interfaces:**
- Consumes: `LibraryRepository` (Task 11), `PdfEngine` (Task 6), `failureMessage` (Task 2)
- Produces: `ViewerScreen({required LibraryDocument document})`; `viewerControllerProvider`; `Future<String?> promptForPassword(BuildContext)`

- [ ] **Step 1: Add ARB strings**

```json
{
  "passwordPromptTitle": "Password required",
  "passwordPromptHint": "Password",
  "passwordPromptOpen": "Open",
  "passwordPromptCancel": "Cancel",
  "viewerPageIndicator": "{current} of {total}",
  "@viewerPageIndicator": {
    "placeholders": { "current": {"type": "int"}, "total": {"type": "int"} }
  },
  "viewerJumpToPage": "Go to page",
  "viewerZoomIn": "Zoom in",
  "viewerZoomOut": "Zoom out",
  "viewerFullScreen": "Full screen",
  "viewerExitFullScreen": "Exit full screen",
  "viewerThumbnails": "Page thumbnails",
  "viewerOutline": "Bookmarks",
  "viewerNoOutline": "This document has no bookmarks.",
  "viewerRotate": "Rotate view",
  "viewerSearch": "Search in document",
  "viewerNoMatches": "No matches",
  "viewerMatchIndicator": "{current} of {total}",
  "@viewerMatchIndicator": {
    "placeholders": { "current": {"type": "int"}, "total": {"type": "int"} }
  },
  "viewerCopyBlocked": "This document does not permit copying.",
  "viewerCopied": "Copied to clipboard"
}
```

- [ ] **Step 2: Implement the password prompt**

`lib/features/viewer/widgets/password_prompt.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';

/// Returns the entered password, or null if the user cancelled.
///
/// The value is passed straight to the engine and never logged or persisted.
Future<String?> promptForPassword(BuildContext context) {
  final controller = TextEditingController();
  final l10n = AppLocalizations.of(context)!;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(l10n.passwordPromptTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(labelText: l10n.passwordPromptHint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.passwordPromptCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(l10n.passwordPromptOpen),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 3: Implement the viewer screen**

`lib/features/viewer/viewer_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/core/errors/failure_messages.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/features/home/providers.dart';
import 'package:folio/features/viewer/widgets/password_prompt.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key, required this.document});

  final LibraryDocument document;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  final _controller = PdfViewerController();
  String? _path;
  AppFailure? _failure;
  bool _fullScreen = false;
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final path = await repo.resolveReadablePath(widget.document);
      await repo.markOpened(widget.document.id);
      if (mounted) setState(() => _path = path);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_failure != null) {
      final message = failureMessage(_failure!, l10n);
      return Scaffold(
        appBar: AppBar(title: Text(widget.document.displayName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(message.body, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    if (_path == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: _fullScreen
          ? null
          : AppBar(
              title: Text(widget.document.displayName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: l10n.viewerZoomOut,
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () => _controller.zoomDown(),
                ),
                IconButton(
                  tooltip: l10n.viewerZoomIn,
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () => _controller.zoomUp(),
                ),
                IconButton(
                  tooltip: l10n.viewerFullScreen,
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () => setState(() => _fullScreen = true),
                ),
              ],
            ),
      body: GestureDetector(
        onDoubleTap: () => _controller.zoomUp(loop: true),
        child: PdfViewer.file(
          _path!,
          controller: _controller,
          params: PdfViewerParams(
            // Never execute embedded JavaScript; render annotations only.
            enableTextSelection: true,
            onDocumentChanged: (doc) {
              if (doc != null && mounted) {
                setState(() => _totalPages = doc.pages.length);
              }
            },
            onPageChanged: (pageNumber) {
              if (pageNumber != null && mounted) {
                setState(() => _currentPage = pageNumber);
              }
            },
          ),
          passwordProvider: () => promptForPassword(context),
        ),
      ),
      bottomNavigationBar: _fullScreen
          ? null
          : BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_totalPages == 0
                      ? ''
                      : l10n.viewerPageIndicator(_currentPage, _totalPages)),
                ],
              ),
            ),
      floatingActionButton: _fullScreen
          ? FloatingActionButton.small(
              tooltip: l10n.viewerExitFullScreen,
              onPressed: () => setState(() => _fullScreen = false),
              child: const Icon(Icons.fullscreen_exit),
            )
          : null,
    );
  }
}
```

Confirm `PdfViewerParams` exposes `enableTextSelection`, `onDocumentChanged` and `onPageChanged` under those exact names in pdfrx 2.4.7 before relying on them; adjust to the real names if they differ and note the change in the commit.

- [ ] **Step 4: Wire navigation from the library**

In `DocumentTile.onTap`:
```dart
onTap: () => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ViewerScreen(document: document),
  ),
),
```

- [ ] **Step 5: Write the integration test**

`integration_test/viewer_open_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  test('a 1000-page document opens and reports its page count', () async {
    final engine = PdfrxEngine();
    final sw = Stopwatch()..start();
    final doc = await engine.open(const FileSource('test_documents/pages_1000.pdf'));
    sw.stop();

    expect(doc.pageCount, 1000);
    expect(sw.elapsedMilliseconds, lessThan(5000),
        reason: 'opening must not take pathologically long');
    await engine.close(doc);
  });

  test('rendering an arbitrary page of a large document is fast', () async {
    final engine = PdfrxEngine();
    final doc = await engine.open(const FileSource('test_documents/pages_1000.pdf'));

    final sw = Stopwatch()..start();
    await engine.renderPage(doc, 750, targetWidthPx: 600, targetHeightPx: 848);
    sw.stop();

    expect(sw.elapsedMilliseconds, lessThan(2000));
    await engine.close(doc);
  });
}
```

- [ ] **Step 6: Verify on the simulator**

Open a PDF from the library. Pinch-zoom, double-tap, scroll, check the page indicator, enter and leave full screen. Open the encrypted fixture and confirm the password prompt appears, that a wrong password re-prompts, and that Cancel returns cleanly without a crash. **Demo this on the simulator.**

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add PDF viewer with zoom, navigation and password flow

Uses pdfrx's PdfViewer widget for rendering, which owns its own tile cache
and scroll physics. Password is passed to the engine and never logged or
persisted. Resolve failures render as localized messages."
```

---

### Task 15: Thumbnails, outline, view rotation and full screen

**Files:**
- Create: `lib/features/viewer/widgets/thumbnail_panel.dart`, `lib/features/viewer/widgets/outline_panel.dart`
- Modify: `lib/features/viewer/viewer_screen.dart`
- Test: `test/features/viewer/outline_flatten_test.dart`

**Interfaces:**
- Consumes: `PdfEngine.outline` (Task 6), `WidthClass` (Task 5), `PdfViewerController` (Task 14)
- Produces: `ThumbnailPanel({required PdfViewerController controller, required int pageCount})`, `OutlinePanel({required List<OutlineNode> nodes, required ValueChanged<int> onJump})`, `List<FlatOutlineEntry> flattenOutline(List<OutlineNode>)`

At `WidthClass.compact` the panels open as a bottom sheet; at medium and expanded they dock as a side rail beside the page.

- [ ] **Step 1: Write the failing outline test**

`test/features/viewer/outline_flatten_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/features/viewer/widgets/outline_panel.dart';

void main() {
  group('flattenOutline', () {
    test('flattens nested nodes depth-first with depth recorded', () {
      const nodes = [
        OutlineNode(title: 'Chapter 1', pageIndex: 0, children: [
          OutlineNode(title: 'Section 1.1', pageIndex: 2, children: []),
          OutlineNode(title: 'Section 1.2', pageIndex: 4, children: []),
        ]),
        OutlineNode(title: 'Chapter 2', pageIndex: 10, children: []),
      ];

      final flat = flattenOutline(nodes);

      expect(flat.map((e) => e.title),
          ['Chapter 1', 'Section 1.1', 'Section 1.2', 'Chapter 2']);
      expect(flat.map((e) => e.depth), [0, 1, 1, 0]);
    });

    test('preserves nodes with no destination', () {
      const nodes = [OutlineNode(title: 'Unlinked', pageIndex: null, children: [])];
      final flat = flattenOutline(nodes);

      expect(flat.single.pageIndex, isNull);
    });

    test('an empty outline flattens to an empty list', () {
      expect(flattenOutline(const []), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/viewer/outline_flatten_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement the outline panel**

`lib/features/viewer/widgets/outline_panel.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/l10n/app_localizations.dart';

class FlatOutlineEntry {
  const FlatOutlineEntry({
    required this.title,
    required this.pageIndex,
    required this.depth,
  });

  final String title;
  final int? pageIndex;
  final int depth;
}

/// Depth-first flattening so the outline renders as an indented list rather
/// than nested expanders, which are awkward on a phone.
List<FlatOutlineEntry> flattenOutline(List<OutlineNode> nodes, {int depth = 0}) {
  final result = <FlatOutlineEntry>[];
  for (final node in nodes) {
    result.add(FlatOutlineEntry(
      title: node.title,
      pageIndex: node.pageIndex,
      depth: depth,
    ));
    result.addAll(flattenOutline(node.children, depth: depth + 1));
  }
  return result;
}

class OutlinePanel extends StatelessWidget {
  const OutlinePanel({super.key, required this.nodes, required this.onJump});

  final List<OutlineNode> nodes;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final flat = flattenOutline(nodes);

    if (flat.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.viewerNoOutline, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.builder(
      itemCount: flat.length,
      itemBuilder: (context, i) {
        final entry = flat[i];
        return ListTile(
          contentPadding: EdgeInsets.only(left: 16.0 + entry.depth * 16, right: 16),
          title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          enabled: entry.pageIndex != null,
          onTap: entry.pageIndex == null ? null : () => onJump(entry.pageIndex!),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/viewer/outline_flatten_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 5: Implement the thumbnail panel**

`lib/features/viewer/widgets/thumbnail_panel.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Lazily rendered page thumbnails.
///
/// Uses a builder-based list so only visible thumbnails are rendered and
/// off-screen bitmaps are released — required by the memory rules in brief
/// section 11 for 1000-page documents.
class ThumbnailPanel extends StatelessWidget {
  const ThumbnailPanel({
    super.key,
    required this.documentRef,
    required this.pageCount,
    required this.currentPage,
    required this.onJump,
  });

  final PdfDocumentRef documentRef;
  final int pageCount;
  final int currentPage;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: pageCount,
      itemExtent: 160,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;
        final isCurrent = pageNumber == currentPage;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Semantics(
            label: 'Page $pageNumber',
            selected: isCurrent,
            child: InkWell(
              onTap: () => onJump(pageNumber),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                child: PdfPageView(
                  documentRef: documentRef,
                  pageNumber: pageNumber,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

Confirm `PdfPageView` and its `documentRef` / `pageNumber` parameters exist in pdfrx 2.4.7 (`lib/src/widgets/pdf_widgets.dart`). If the widget is named differently, adjust and note it in the commit.

- [ ] **Step 6: Dock the panels in the viewer**

In `ViewerScreen`, add a `_SidePanel` enum (`none`, `thumbnails`, `outline`), toolbar buttons for each, and render based on width class: `showModalBottomSheet` at `WidthClass.compact`, otherwise a fixed-width `SizedBox(width: 240)` in a `Row` beside the `PdfViewer`. Add a rotate-view button that cycles a quarter-turn counter applied with `RotatedBox` around the viewer — **view only, the file is never written**.

- [ ] **Step 7: Verify on the simulator**

Open the 100-page fixture, scroll the thumbnail panel, jump by tapping a thumbnail, open the outline on a document that has one, and confirm the no-bookmarks message on one that does not. Rotate the view and confirm the file on disk is unchanged (`shasum` before and after). **Demo this on the simulator.**

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add thumbnails, outline, view rotation and full screen

Thumbnails render lazily via a builder list so 1000-page documents do not
hold every bitmap. Outline flattens depth-first into an indented list.
Rotation is view-only and never touches the file."
```

---

### Task 16: In-document search, text selection and copy

**Files:**
- Create: `lib/features/viewer/widgets/search_bar.dart`
- Modify: `lib/features/viewer/viewer_screen.dart`
- Test: `integration_test/viewer_search_test.dart`

**Interfaces:**
- Consumes: `PdfTextSearcher` (pdfrx), `PdfEngine.permissions` (Task 6), `PdfEngine.extractText` (Task 6)
- Produces: `ViewerSearchBar({required PdfTextSearcher searcher, required VoidCallback onClose})`

- [ ] **Step 1: Implement the search bar**

`lib/features/viewer/widgets/search_bar.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:folio/l10n/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

class ViewerSearchBar extends StatefulWidget {
  const ViewerSearchBar({super.key, required this.searcher, required this.onClose});

  final PdfTextSearcher searcher;
  final VoidCallback onClose;

  @override
  State<ViewerSearchBar> createState() => _ViewerSearchBarState();
}

class _ViewerSearchBarState extends State<ViewerSearchBar> {
  final _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.searcher.addListener(_onSearcherChanged);
  }

  void _onSearcherChanged() => setState(() {});

  @override
  void dispose() {
    widget.searcher.removeListener(_onSearcherChanged);
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searcher = widget.searcher;
    final total = searcher.matches.length;
    final current = searcher.currentIndex;

    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _field,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.viewerSearch,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value.isEmpty) {
                    searcher.resetTextSearch();
                  } else {
                    searcher.startTextSearch(value, caseInsensitive: true);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              total == 0
                  ? (_field.text.isEmpty ? '' : l10n.viewerNoMatches)
                  : l10n.viewerMatchIndicator((current ?? 0) + 1, total),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: !searcher.hasMatches || current == null || current == 0
                  ? null
                  : () => searcher.goToMatch(searcher.matches[current - 1]),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: !searcher.hasMatches || current == null || current >= total - 1
                  ? null
                  : () => searcher.goToMatch(searcher.matches[current + 1]),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire the searcher into the viewer**

In `_ViewerScreenState`, create `late final _searcher = PdfTextSearcher(_controller)..addListener(...)`, dispose it in `dispose()`, add a search toolbar button that toggles a `_searchOpen` flag, render `ViewerSearchBar` above the viewer when open, and register the highlight painter in `PdfViewerParams`:

```dart
pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
```

- [ ] **Step 3: Respect the document's copy permission**

Text selection is enabled via `PdfViewerParams.enableTextSelection`. Before allowing a copy, check `PdfEngine.permissions`: when `allowsCopying` is false, block the copy and show `l10n.viewerCopyBlocked`. A document that forbids copying must not have its text extracted to the clipboard by this app.

- [ ] **Step 4: Write the integration test**

`integration_test/viewer_search_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  test('finds a token that appears on exactly one page', () async {
    final engine = PdfrxEngine();
    final doc = await engine.open(const FileSource('test_documents/sample_3page.pdf'));

    var foundOn = -1;
    for (var i = 0; i < doc.pageCount; i++) {
      final text = await engine.extractText(doc, i);
      if (text != null && text.fullText.contains('PLATYPUS-TOKEN-42')) {
        foundOn = i;
        break;
      }
    }

    expect(foundOn, 2);
    await engine.close(doc);
  });

  test('a scanned page with no text layer yields empty text rather than failing', () async {
    final engine = PdfrxEngine();
    final doc = await engine.open(const FileSource('test_documents/scanned_no_text.pdf'));

    final text = await engine.extractText(doc, 0);
    expect(text?.fullText ?? '', isEmpty,
        reason: 'search finding nothing in a scan is correct until OCR lands in SP-6');
    await engine.close(doc);
  });

  test('char rects align one-to-one with the extracted text', () async {
    final engine = PdfrxEngine();
    final doc = await engine.open(const FileSource('test_documents/sample_3page.pdf'));

    final text = await engine.extractText(doc, 0);
    expect(text!.charRects.length, text.fullText.length,
        reason: 'selection and highlighting depend on this alignment');
    await engine.close(doc);
  });
}
```

- [ ] **Step 5: Verify on the simulator**

Search for a term, step through matches with the arrows, confirm highlights appear on the page, select text with a long-press drag, and copy. Open the permission-restricted fixture and confirm copy is blocked with a message. **Demo this on the simulator.**

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add in-document search, text selection and copy

Search highlights use pdfrx's page paint callback. Copy checks the
document's own allowsCopying permission and is blocked with a message when
the document forbids it."
```

---

# Stage 5 — Validation, licensing and documentation

Ends with: every Definition-of-Done box in the spec ticked, or explicitly recorded as a limitation.

---

### Task 17: Fixture generator and robustness validation

**Files:**
- Create: `scripts/make_fixtures.dart`, `scripts/rc4_encrypt.dart`
- Create: `test_documents/.gitignore`
- Test: `test/scripts/fixture_generator_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `test_documents/` populated with `sample_3page.pdf`, `pages_1.pdf`, `pages_10.pdf`, `pages_100.pdf`, `pages_500.pdf`, `pages_1000.pdf`, `pages_5000.pdf`, `image_heavy.pdf`, `scanned_no_text.pdf`, `encrypted_user_pw.pdf`, `no_copy_permission.pdf`, `corrupt_truncated.pdf`, `malformed_xref.pdf`, `embedded_javascript.pdf`

Fixtures are **generated, not committed** — `test_documents/.gitignore` contains `*` with an exception for itself. This keeps the repository small and the inputs reproducible.

- [ ] **Step 1: Write the failing generator test**

`test/scripts/fixture_generator_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fixture generator output', () {
    setUpAll(() async {
      final result = await Process.run('dart', ['run', 'scripts/make_fixtures.dart']);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('generates every fixture the test suite references', () {
      const required = [
        'sample_3page.pdf',
        'pages_1.pdf',
        'pages_100.pdf',
        'pages_1000.pdf',
        'scanned_no_text.pdf',
        'encrypted_user_pw.pdf',
        'corrupt_truncated.pdf',
        'malformed_xref.pdf',
        'embedded_javascript.pdf',
      ];
      for (final name in required) {
        expect(File('test_documents/$name').existsSync(), isTrue,
            reason: '$name was not generated');
      }
    });

    test('valid fixtures start with the PDF header', () {
      final bytes = File('test_documents/sample_3page.pdf').readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
    });

    test('the corrupt fixture is deliberately truncated', () {
      final bytes = File('test_documents/corrupt_truncated.pdf').readAsBytesSync();
      expect(String.fromCharCodes(bytes), isNot(contains('%%EOF')));
    });

    test('the 1000-page fixture really has 1000 page objects', () {
      final text = File('test_documents/pages_1000.pdf').readAsStringSync(encoding: latin1);
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 1000);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/scripts/fixture_generator_test.dart`
Expected: FAIL — the script does not exist

- [ ] **Step 3: Implement the generator**

`scripts/make_fixtures.dart` builds PDFs by emitting objects and an xref table directly — no PDF library is needed to produce simple valid files, and writing them by hand gives exact control over the malformed cases.

Structure:
```dart
import 'dart:convert';
import 'dart:io';

/// Emits a minimal but valid PDF: catalog, page tree, one content stream per
/// page, and a Helvetica font resource.
List<int> buildPdf(List<({String title, String body})> pages) {
  final objects = <String>[];
  objects.add('<< /Type /Catalog /Pages 2 0 R >>');

  final kids = List.generate(pages.length, (i) => '${3 + i * 2} 0 R').join(' ');
  objects.add('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>');

  final fontObj = 3 + pages.length * 2;
  for (var i = 0; i < pages.length; i++) {
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 $fontObj 0 R >> >> '
        '/Contents ${4 + i * 2} 0 R >>');
    final stream = 'BT /F1 24 Tf 60 760 Td (${pages[i].title}) Tj ET\n'
        'BT /F1 12 Tf 60 700 Td (${pages[i].body}) Tj ET\n'
        'BT /F1 10 Tf 60 60 Td (Page ${i + 1} of ${pages.length}) Tj ET\n';
    objects.add('<< /Length ${stream.length} >>\nstream\n${stream}endstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  return assemble(objects, '<< /Size ${objects.length + 1} /Root 1 0 R >>');
}

/// Writes the object bodies, then a correct xref table and trailer.
List<int> assemble(List<String> objects, String trailerDict) {
  final out = <int>[...latin1.encode('%PDF-1.4\n')];
  final offsets = <int>[];

  for (var n = 0; n < objects.length; n++) {
    offsets.add(out.length);
    out.addAll(latin1.encode('${n + 1} 0 obj\n${objects[n]}\nendobj\n'));
  }

  final xrefStart = out.length;
  out.addAll(latin1.encode('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n'));
  for (final off in offsets) {
    out.addAll(latin1.encode('${off.toString().padLeft(10, '0')} 00000 n \n'));
  }
  out.addAll(latin1.encode('trailer\n$trailerDict\nstartxref\n$xrefStart\n%%EOF\n'));
  return out;
}
```

Then generate each fixture:

- **`sample_3page.pdf`** — three pages whose third body contains the exact string `Searchable marker string: PLATYPUS-TOKEN-42 appears only here.` The integration tests in Tasks 7 and 16 assert on this token, so it must not change.
- **`pages_N.pdf`** for N in 1, 10, 100, 500, 1000, 5000 — `buildPdf` with N generated pages.
- **`image_heavy.pdf`** — pages each carrying a large embedded `/DCTDecode` JPEG XObject.
- **`scanned_no_text.pdf`** — pages containing only an image XObject and **no text-showing operators**, so text extraction correctly returns empty.
- **`corrupt_truncated.pdf`** — take `sample_3page.pdf` and cut the last 200 bytes, removing `%%EOF` and part of the xref.
- **`malformed_xref.pdf`** — valid objects, but every xref offset is overwritten with a wrong value.
- **`embedded_javascript.pdf`** — a catalog carrying `/Names << /JavaScript << /Names [(evil) << /S /JavaScript /JS (app.alert\('should never run'\);) >>] >> >>`. The app must open this without executing anything.
- **`no_copy_permission.pdf`** and **`encrypted_user_pw.pdf`** — see the next step.

- [ ] **Step 4: Implement RC4 encryption for the protected fixtures**

`scripts/rc4_encrypt.dart` implements the PDF standard security handler, revision 2 (RC4, 40-bit), per ISO 32000-1 §7.6.3. This is real work — roughly 100 lines — and there is no shortcut, because no free Dart package produces an encrypted PDF and no encryption tool is installed on this machine.

Required pieces:
1. **RC4** — key-scheduling plus the pseudo-random generation loop, about 20 lines.
2. **MD5** — from `package:crypto`.
3. **Algorithm 2** (compute the encryption key): pad the user password to 32 bytes with the standard pad string, append the owner password hash `/O`, append `/P` as a 4-byte little-endian signed integer, append the first document ID, then MD5 the result and take the first 5 bytes.
4. **Algorithm 4** (compute `/U`): RC4-encrypt the 32-byte pad string with the encryption key.
5. **Algorithm 3** (compute `/O`): derive from the owner password.
6. Encrypt each string and stream with a per-object key: MD5 of `key + objNum(3 bytes LE) + genNum(2 bytes LE)`, truncated to `min(keyLength + 5, 16)`.
7. Emit `/Encrypt << /Filter /Standard /V 1 /R 2 /O <...> /U <...> /P -44 >>` in the trailer along with `/ID [<...> <...>]`.

Use user password `folio-test` for `encrypted_user_pw.pdf` — the integration test in Task 7 expects exactly that string.

For `no_copy_permission.pdf`, use an **empty user password** so it opens without a prompt, and set `/P` with bit 5 (value 16, print) set but bit 3 (value 4, copy) cleared, so `allowsCopying` reports false while the document still opens freely. This is what Task 16's copy-blocking path is tested against.

- [ ] **Step 5: Run to verify it passes**

Run: `dart run scripts/make_fixtures.dart && flutter test test/scripts/fixture_generator_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 6: Run the robustness matrix against the real engine**

Add `integration_test/robustness_test.dart` asserting that each malformed fixture produces a typed failure rather than a crash:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  for (final name in const ['corrupt_truncated.pdf', 'malformed_xref.pdf']) {
    test('$name fails safely with a typed failure', () async {
      final engine = PdfrxEngine();
      await expectLater(
        engine.open(FileSource('test_documents/$name')),
        throwsA(isA<AppFailure>()),
        reason: 'malformed input must never crash the process',
      );
    });
  }

  test('a PDF carrying JavaScript opens without executing it', () async {
    final engine = PdfrxEngine();
    final doc = await engine.open(
        const FileSource('test_documents/embedded_javascript.pdf'));
    expect(doc.pageCount, greaterThan(0));
    await engine.close(doc);
  });

  test('the 5000-page fixture opens without exhausting memory', () async {
    final engine = PdfrxEngine();
    final doc = await engine.open(const FileSource('test_documents/pages_5000.pdf'));
    expect(doc.pageCount, 5000);
    // Render pages spread across the document rather than sequentially, which is
    // the access pattern most likely to defeat a naive cache.
    for (final index in [0, 2500, 4999, 1, 4998]) {
      final img = await engine.renderPage(doc, index,
          targetWidthPx: 400, targetHeightPx: 566);
      expect(img.widthPx, 400);
    }
    await engine.close(doc);
  });
}
```

Run on the simulator and watch memory in DevTools. If the 5000-page case exhausts memory, that is a real finding — record it in `docs/LIMITATIONS.md` with the observed page ceiling rather than quietly dropping the fixture.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: add fixture generator and robustness matrix

Fixtures are generated rather than committed. Includes deliberately
malformed, encrypted, permission-restricted and JavaScript-carrying PDFs.
RC4 standard security handler implemented in the generator because no free
Dart package produces encrypted PDFs."
```

---

### Task 18: End-to-end flows and offline validation

**Files:**
- Create: `integration_test/end_to_end_test.dart`
- Create: `docs/TESTING.md`
- Test: this task is the test

**Interfaces:**
- Consumes: everything built so far
- Produces: `docs/TESTING.md` recording how to run each suite and what each covers

- [ ] **Step 1: Write the end-to-end flows**

These are the SP-1-applicable subset of the brief's §30 integration tests. Flows covering merge, split, rotation persistence, signatures, OCR, encryption authoring and redaction belong to SP-2 through SP-6 and are deliberately absent.

`integration_test/end_to_end_test.dart` covers:

1. **Import → list → open → read.** Import a fixture, confirm it appears in the library, open it, confirm the first page renders and the page indicator reads `1 of 3`.
2. **Recents survive relaunch.** Open a document, restart the app in the test harness, confirm it appears under Recent.
3. **Favorite round-trip.** Star a document, restart, confirm it is still starred.
4. **Rename.** Rename a document, confirm the list updates and the file on disk is unchanged.
5. **Delete.** Delete a document, confirm the row and the managed copy are both gone.
6. **Duplicate.** Duplicate a document, confirm two independent entries with different managed paths.
7. **Search across the library.** Type a query, confirm filtering; clear it, confirm everything returns.
8. **Password flow.** Open `encrypted_user_pw.pdf`, supply the wrong password and confirm a re-prompt, then the right one and confirm it opens.
9. **Corrupt file.** Open `corrupt_truncated.pdf`, confirm a friendly message appears and no stack trace is visible.
10. **Copy restriction.** Open `no_copy_permission.pdf`, attempt a copy, confirm it is blocked with the localized message.

Each flow uses `IntegrationTestWidgetsFlutterBinding`, drives real widgets with `tester.tap` and `tester.pumpAndSettle`, and asserts on visible text rather than internal state.

- [ ] **Step 2: Run the full integration suite on the simulator**

```bash
dart run scripts/make_fixtures.dart
flutter test integration_test -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all flows pass. **Demo this on the simulator.**

- [ ] **Step 3: Run the same suite on the Android AVD**

```bash
flutter emulators --launch pixel_api35
flutter test integration_test -d emulator-5554
```

Expected: all flows pass. Any Android-only failure is likely SAF-related — check Task 10's persisted grants first. Until this step passes, no Android claim may be made anywhere in the documentation.

- [ ] **Step 4: Validate offline operation**

Per brief §20 and §27, with the simulator's network disabled:

```bash
# macOS: disable the host's network, or use the simulator's own network conditioner
sudo ifconfig en0 down
flutter test integration_test -d DFC5606D-37F0-4176-A73D-B8214C7F820F
sudo ifconfig en0 up
```

Every flow must pass unchanged. If anything fails, an accidental network dependency has crept in — find it and remove it. Note that `flutter run` itself needs a connection to install; run the app first, then disable the network, then exercise it by hand.

- [ ] **Step 5: Write docs/TESTING.md**

Record: how to generate fixtures, how to run unit versus integration suites, which device each requires, the current coverage figure with the command that produced it, and the explicit statement that Windows has unit and build coverage only.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "test: add end-to-end flows and offline validation

Ten flows covering import, read, recents, favorites, rename, delete,
duplicate, search, password and copy restriction. Verified on the iOS
simulator and the Android AVD, with the network disabled."
```

---

### Task 19: Licence audit, documentation and the Definition of Done

**Files:**
- Modify: `scripts/check_licenses.dart` (replace the Task 1 stub)
- Create: `README.md`, `docs/ARCHITECTURE.md`, `docs/FEATURES.md`, `docs/SECURITY.md`, `docs/PRIVACY.md`, `docs/LIMITATIONS.md`, `docs/BUILD_WINDOWS.md`, `docs/BUILD_ANDROID.md`, `docs/BUILD_IOS.md`, `docs/BUILD_IPADOS.md`, `docs/RELEASE.md`
- Modify: `docs/THIRD_PARTY_LICENSES.md`
- Test: `test/scripts/check_licenses_test.dart`

**Interfaces:**
- Consumes: the whole project
- Produces: a licence checker that fails CI on copyleft, and the documentation set required by brief §39

- [ ] **Step 1: Write the failing licence-checker test**

`test/scripts/check_licenses_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('check_licenses', () {
    test('passes on the current dependency set', () async {
      final result = await Process.run('dart', ['run', 'scripts/check_licenses.dart']);
      expect(result.exitCode, 0,
          reason: 'a copyleft dependency has entered the tree:\n${result.stdout}');
    });

    test('every direct dependency appears in THIRD_PARTY_LICENSES.md', () async {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final licenses = File('docs/THIRD_PARTY_LICENSES.md').readAsStringSync();

      final deps = RegExp(r'^  ([a-z_0-9]+):', multiLine: true)
          .allMatches(pubspec)
          .map((m) => m.group(1)!)
          .where((d) => d != 'flutter' && d != 'sdk')
          .toSet();

      final undocumented = deps.where((d) => !licenses.contains(d)).toList();
      expect(undocumented, isEmpty,
          reason: 'undocumented dependencies: $undocumented');
    });
  });
}
```

- [ ] **Step 2: Implement the checker**

`scripts/check_licenses.dart` reads `.dart_tool/package_config.json`, locates each package in the pub cache, reads its `LICENSE` file, and fails on any match for GPL, LGPL, AGPL, SSPL, or a commercial-licence marker. Maintain an explicit deny list:

```dart
const denied = <String>[
  'GNU GENERAL PUBLIC LICENSE',
  'GNU LESSER GENERAL PUBLIC',
  'GNU AFFERO',
  'Server Side Public License',
  'Syncfusion',   // proprietary; rejected in the spec
  'PSPDFKit',
  'Apryse',
  'PDFTron',
];
```

Print every package with its detected licence so the CI log doubles as an audit trail, then exit non-zero if anything matched.

- [ ] **Step 3: Run to verify it passes**

Run: `flutter test test/scripts/check_licenses_test.dart`
Expected: PASS — 2 tests

- [ ] **Step 4: Write the documentation set**

- **`README.md`** — what it is, what it deliberately is not (no AI, no cloud, no account), supported platforms with their honest verification status, and quick-start build commands.
- **`docs/ARCHITECTURE.md`** — the layer diagram, the `PdfEngine` boundary and why it has no write method, the deliberate `PdfViewer` exception from Task 12, and the `DocumentRef` model.
- **`docs/FEATURES.md`** — the SP-1 feature matrix with a column per platform, marking Windows as *built and unit-tested, not manually verified*.
- **`docs/SECURITY.md`** — PDFs treated as untrusted input; JavaScript never executed; which encryption standards are *read* (RC4 40/128, AES-128, AES-256 via PDFium) and the explicit statement that **SP-1 cannot author encryption**. No "military-grade" claims anywhere.
- **`docs/PRIVACY.md`** — no network, no account, no telemetry, no analytics; documents never leave the device; what is logged and what is never logged.
- **`docs/LIMITATIONS.md`** — the six limitations from spec §15, plus anything discovered during Tasks 17 and 18, notably any page-count ceiling found on the 5000-page fixture.
- **`docs/BUILD_WINDOWS.md`** — must state plainly that Windows builds cannot be produced on the development machine and are made by CI, with the workflow file named.
- **`docs/BUILD_ANDROID.md`**, **`docs/BUILD_IOS.md`**, **`docs/BUILD_IPADOS.md`** — exact commands including `--dart-define-from-file`, with signing covered separately.
- **`docs/RELEASE.md`** — the release checklist mapped to brief §42.

- [ ] **Step 5: Verify the Definition of Done**

Walk spec §14 item by item and confirm each with a command, not a recollection:

```bash
flutter analyze                      # zero errors
flutter test --coverage              # all pass; check domain/ and data/ >= 80%
dart run scripts/check_licenses.dart # zero copyleft
flutter test integration_test -d DFC5606D-37F0-4176-A73D-B8214C7F820F
flutter test integration_test -d emulator-5554
gh run list --limit 1                # Windows CI green
```

Any box that cannot be ticked moves to `docs/LIMITATIONS.md` with the reason. **Do not tick a box you have not run the command for.**

- [ ] **Step 6: Final simulator demonstration**

Walk the whole app end to end on the simulator: import, browse, search, sort, favorite, open, zoom, thumbnails, outline, in-document search, select and copy, password-protected open, corrupt-file handling. **Demo this on the simulator.**

- [ ] **Step 7: Commit and tag**

```bash
git add -A
git commit -m "docs: complete SP-1 documentation and licence audit

Licence checker fails CI on GPL/LGPL/AGPL/SSPL and on the commercial PDF
SDKs rejected in the spec. Documentation records Windows as built and
unit-tested but never manually verified."
git tag -a sp1-complete -m "SP-1: Foundation + Viewer"
```

---

## Definition of Done for this plan

SP-1 is complete when every box in spec §14 is ticked with a command that was actually run, and everything that could not be ticked is recorded in `docs/LIMITATIONS.md`.

Report the phase status in the format the brief requires:

```
PHASE STATUS
------------
Implemented:
Tests:
Platforms Verified:
Known Issues:
Dependencies Added:
License:
Next Phase:
```

**Next:** SP-2 — the Dart PDF object layer and page operations. Its spec is written only after SP-1 ships, so it can be informed by what the viewer actually taught us.
