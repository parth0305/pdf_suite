# Known Limitations

Stated plainly. A feature absent from this list is not thereby guaranteed to
work; see `FEATURES.md` for what is claimed and `TESTING.md` for what was
actually verified.

## 1. Windows has no manual QA — and never will on this machine

Flutter Windows builds require Windows plus Visual Studio 2022. The development
machine is an Intel Mac. Windows is verified **only** by the GitHub Actions
`windows-latest` runner, which compiles the app and runs unit tests.

Unverified on Windows: mouse interaction, keyboard navigation, touchscreen,
File Explorer drag-and-drop, printing, and the batch UI. macOS desktop is used
as a stand-in for verifying the expanded-width layout, but it is a different
platform and not a shipping target.

## 2. SP-1 does not modify PDFs at all

By design. `PdfEngine` has no write method. Merging, splitting, annotating,
signing, redacting, compressing and encrypting are later sub-projects. View
rotation is not persisted to the file.

## 3. Search finds nothing in scanned documents

A PDF with no text layer yields empty text. This is correct behaviour, not a
bug — OCR arrives in SP-6. The `scanned_no_text.pdf` fixture asserts it returns
empty rather than failing.

## 4. Android open-in-place requires a SAF URI

`PlatformHandles.capture()` on Android accepts only a `content://` URI from the
system picker. A filesystem path cannot be granted a persistable permission, so
it is rejected with `UnsupportedFeature` rather than producing a handle that
would fail silently on next launch.

## 5. English only

The architecture supports localisation — all strings live in ARB files from the
first commit — but no translations exist.

## 6. Both native dependencies use Dart native assets

`pdfrx` (PDFium) and `sqlite3` (via drift) build through Dart's newer native
assets / build hooks mechanism rather than classic Flutter plugins. The iOS
build emits a non-fatal `Target native_assets required define SdkRoot but it
was not provided`. Both currently build green on all four platforms including
the Windows runner, but this is the most likely source of future
cross-platform build breakage.

## 7. Encryption is generated, not authored by the app

The RC4 standard-security-handler implementation in `scripts/` exists solely to
produce encrypted test fixtures. The application cannot apply encryption to a
document; it can only read encrypted documents. Authoring encryption is SP-5.

## 8. Test fixtures are generated, not committed

`test_documents/` is gitignored. Run `dart run scripts/make_fixtures.dart`
before any test that needs host-side fixtures. Integration tests build their
own fixtures on-device via the same pure builder, so no test data ships in
release builds.
