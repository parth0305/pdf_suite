# Release

## Gate

No release proceeds until every command below has actually been run and its
output inspected. A checkbox ticked from memory is not evidence.

```bash
# 1. Analyzer must be clean at the strictness CI enforces
flutter analyze --fatal-infos

# 2. Formatting must match CI
dart format --set-exit-if-changed lib test integration_test scripts

# 3. Unit tests and coverage
flutter test --coverage

# 4. Licence audit — fails on GPL/LGPL/AGPL/SSPL and commercial PDF SDKs
dart run scripts/check_licenses.dart

# 5. Fixtures, then integration on every device available
dart run scripts/make_fixtures.dart
flutter test integration_test -d <ios-simulator>
flutter test integration_test -d emulator-5554

# 6. Confirm CI is green, including build-windows
gh pr checks <pr-number>
```

## Offline verification

Core functionality must work with networking disabled. Run the app, disable the
host network, then exercise open, search, select, favourite and delete by hand.
`flutter run` itself needs a connection to install, so install first and
disconnect after.

## Signing

**A release build is UNSIGNED until you provide a keystore.** The Flutter
template signs release builds with the *debug* key, which cannot be published
and is shared by every Flutter developer in the world — anyone could forge an
update to an app signed with it. Folio removed that: without a keystore the
release build comes out unsigned and fails loudly at install time, rather than
looking like a release until someone tries to publish it.

Create `android/key.properties` (gitignored — it names a keystore and holds its
passwords):

```properties
storeFile=/absolute/path/to/folio-release.jks
storePassword=...
keyAlias=folio
keyPassword=...
```

Verify a build really is signed before publishing it — the absence of a
signature block is the failure this guards against:

```bash
unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  | grep -E 'META-INF/.*\.(RSA|DSA|EC)'
```

## Release builds

```bash
# Play Store: an app bundle, which splits per ABI on the store side.
flutter build appbundle --release --dart-define-from-file=config/production.json

# Direct distribution: split per ABI. A universal APK carries all three.
flutter build apk --release --split-per-abi \
  --dart-define-from-file=config/production.json

flutter build ios --release --dart-define-from-file=config/production.json
# Windows is produced by CI only — see BUILD_WINDOWS.md
```

### Size, measured

Folio bundles PDFium and Tesseract natively, so it is not a small app. Measured
on 2026-08-27:

| Build | Size |
|---|---|
| Universal APK (all three ABIs) | 102 MB |
| `arm64-v8a` only | 37 MB |
| `armeabi-v7a` only | 31 MB |
| `x86_64` only | 39 MB |

**Never publish the universal APK.** It triples the download for no benefit —
every device uses exactly one ABI. Roughly 15 MB of each split is
PDFium plus Tesseract's native library, and 3.9 MB is the English OCR model.

## Before declaring a release complete

- [ ] No analyzer errors or infos
- [ ] No failing tests on any platform that has a test path
- [ ] Licence audit passes
- [ ] Corruption fixtures fail safely rather than crashing
      (`corrupt_truncated.pdf`, `malformed_xref.pdf` — both exercised by the
      integration suite, so a green run covers this)
- [ ] Password-protected documents open correctly (`encrypted_user_pw.pdf`)
- [ ] Large-document fixtures open without exhausting memory
      (`pages_1000.pdf` — exercised by `pdfrx_engine_test` and
      `page_editor_test`)
- [ ] A document with embedded JavaScript opens without executing anything
      (`embedded_javascript.pdf`)
- [ ] Offline operation verified by hand
- [ ] `FEATURES.md` status marks match what was actually verified
- [ ] `LIMITATIONS.md` lists every known gap, including anything discovered
      during this release
- [ ] `THIRD_PARTY_LICENSES.md` covers every direct dependency
- [ ] The release build is **signed** — check for the signature block, do not
      assume it
- [ ] iOS usage descriptions are present for camera and photo library —
      without them iOS **terminates the app** when the scanner opens
      (`test/platform/permission_declarations_test.dart` enforces this).
      Confirm they reached the bundle, not just the source:
      `plutil -extract NSCameraUsageDescription raw build/ios/iphoneos/Runner.app/Info.plist`
- [ ] An app bundle or per-ABI APKs, never the universal APK
- [ ] Every localised string is shown somewhere
      (`test/l10n/strings_are_shown_test.dart` enforces this — a string the app
      never displays cannot back a claim the documentation makes)

## Honesty rule

`FEATURES.md` distinguishes ✅ verified from 🟡 built-but-unexercised. Windows
is 🟡 throughout and must stay that way until someone runs the app on Windows.
Do not promote a status because a build passed.
