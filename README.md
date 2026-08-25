# Folio

A privacy-focused, offline-first PDF reader for iPhone, iPad, Android and Windows.

Folio processes documents entirely on your device. There is no account, no
cloud, no telemetry, and no AI of any kind.

## What it is

SP-1 ships a **reader**. It opens, displays, searches and organises PDFs. It
does not modify document content — the PDF engine interface has no write method
at all, so a bug cannot corrupt your files.

## What it deliberately is not

- **No AI.** No LLM, no chat-with-PDF, no AI summarisation, no AI OCR.
- **No cloud.** No backend, no account, no sync, no analytics.
- **No paid or proprietary SDK.** Every dependency is MIT, BSD or Apache-2.0.
- **Not an Acrobat clone.** Original interface; no copied UI, icons or assets.

## Platform status

| Platform | Build | Automated tests | Manual QA |
|---|---|---|---|
| iOS / iPadOS | ✅ | ✅ on simulator | ✅ |
| Android | ✅ | ✅ on emulator | ✅ |
| Windows | ✅ CI only | ✅ unit only | ❌ **none — see LIMITATIONS.md** |
| macOS | ✅ | ✅ | ✅ (desktop-layout stand-in, not a shipping target) |

## Quick start

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define-from-file=config/development.json
```

## Documentation

| Document | Contents |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layering, the engine boundary, document identity |
| [DEVELOPMENT_SETUP.md](docs/DEVELOPMENT_SETUP.md) | Verified toolchain and environment gaps |
| [FEATURES.md](docs/FEATURES.md) | Feature matrix with honest verification status |
| [TESTING.md](docs/TESTING.md) | How to run each suite and what it covers |
| [SECURITY.md](docs/SECURITY.md) | Untrusted input handling; what encryption is supported |
| [PRIVACY.md](docs/PRIVACY.md) | What is stored and what is logged |
| [LIMITATIONS.md](docs/LIMITATIONS.md) | Known gaps, stated plainly |
| [THIRD_PARTY_LICENSES.md](docs/THIRD_PARTY_LICENSES.md) | Every dependency and its licence |
| [BUILD_WINDOWS.md](docs/BUILD_WINDOWS.md) | Windows builds (CI only) |
| [BUILD_ANDROID.md](docs/BUILD_ANDROID.md) | Android builds |
| [BUILD_IOS.md](docs/BUILD_IOS.md) | iOS and iPadOS builds |
| [RELEASE.md](docs/RELEASE.md) | Release checklist |
