# Folio

A privacy-focused, offline-first PDF reader for iPhone, iPad, Android and Windows.

Folio processes documents entirely on your device. There is no account, no
cloud, no telemetry, and no AI of any kind.

## What it is

Folio opens, displays, searches and organises PDFs, and rearranges their pages:
merge, split, reorder, delete, extract, rotate, duplicate and insert.

**Every operation produces a new document and leaves the original
byte-identical**, asserted by SHA-256 in the test suite. Nothing overwrites your
files.

Reading and writing are separate by construction. The `PdfEngine` interface used
throughout the reader has **no write method at all**, so no amount of viewing,
searching or browsing can alter a document. Page editing goes through a separate
`PdfPageEditor`, and edits are staged in memory until you explicitly save — an
abandoned edit writes nothing.

Document metadata — title, author, subject, keywords — is carried through page
operations. Folio never adds a `/Producer` or `/ModDate` of its own: a document
you edit does not start advertising which tool touched it, or when.

Not yet possible: printing and batch processing. Compression is lossless only —
Folio will not reduce image quality to shrink a file. Scanned documents have no text layer until you run OCR on them,
which happens entirely on your device. See [FEATURES.md](docs/FEATURES.md) for what is
implemented and verified on which platform.

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
