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

## Release builds

```bash
flutter build apk --release       --dart-define-from-file=config/production.json
flutter build appbundle --release --dart-define-from-file=config/production.json
flutter build ios --release       --dart-define-from-file=config/production.json
# Windows is produced by CI only — see BUILD_WINDOWS.md
```

## Before declaring a release complete

- [ ] No analyzer errors or infos
- [ ] No failing tests on any platform that has a test path
- [ ] Licence audit passes
- [ ] Corruption fixtures fail safely rather than crashing
- [ ] Password-protected documents open correctly
- [ ] Large-document fixtures open without exhausting memory
- [ ] Offline operation verified by hand
- [ ] `FEATURES.md` status marks match what was actually verified
- [ ] `LIMITATIONS.md` lists every known gap, including anything discovered
      during this release
- [ ] `THIRD_PARTY_LICENSES.md` covers every direct dependency

## Honesty rule

`FEATURES.md` distinguishes ✅ verified from 🟡 built-but-unexercised. Windows
is 🟡 throughout and must stay that way until someone runs the app on Windows.
Do not promote a status because a build passed.
