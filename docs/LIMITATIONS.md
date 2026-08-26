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

## 2. Page operations exist; content editing does not

SP-2a added merge, split, reorder, delete, extract, rotate, duplicate and
insert. Every one produces a **new** document and leaves its source
byte-identical.

Still absent: annotations, signatures, metadata editing, encryption authoring,
redaction, compression, watermarks and OCR. Those are SP-2b onward.

`PdfEngine` remains read-only and has no write method; all writing goes through
the separate `PdfPageEditor`, so the reader still cannot alter a document.

View rotation in read mode is not persisted — rotating in Pages mode and saving
is what writes rotation to a file.

## 3. Markup cannot be added to newer PDFs, and cannot be edited once saved

A page whose `/Annots` is an **indirect reference** (`/Annots 9 0 R`, common
from other producers) is refused rather than annotated. Folio's merge emits an
inline array, which would replace that reference and orphan every annotation it
holds. Resolving indirect arrays would lift this.

Annotations are attached by a PDF **incremental update**, which assumes a classic
cross-reference table. Documents using PDF 1.5+ cross-reference streams are
**refused with a clear message** rather than silently producing a file whose
annotations never appear.

Saved annotations can be deleted, and their colour and thickness changed, but
their **geometry cannot be edited** — nothing can be moved, resized or
reshaped. Delete and redraw instead.

Restyling is offered only for annotations whose geometry Folio can read back:
markup, ink, squares, circles and lines. Any other subtype is delete-only,
because regenerating an appearance for a subtype Folio does not model would
change how another tool's annotation renders.

Signatures are **drawn only**. Photographing a signature on paper is not
supported: it needs image embedding and background removal, and is scoped as its
own slice.

A Folio signature is a picture of your signature, not a cryptographic one. It
proves nothing about identity and is not a digital signature in the legal sense.

A signature captured in a small canvas and placed very large may show faceting
where its samples were taken.

Each edit supersedes an appearance stream and leaves the old one in the file,
so repeatedly editing one document grows it slowly. Nothing is compacted.

Appearance streams are generated for every markup. PDFium renders markup without
them, but portability to other viewers could not be measured on this machine, and
portability is the whole reason annotations are written into the file.

## 4. Search finds nothing in scanned documents

A PDF with no text layer yields empty text. This is correct behaviour, not a
bug — OCR arrives in SP-6. The `scanned_no_text.pdf` fixture asserts it returns
empty rather than failing.

## 5. Android open-in-place requires a SAF URI

`PlatformHandles.capture()` on Android accepts only a `content://` URI from the
system picker. A filesystem path cannot be granted a persistable permission, so
it is rejected with `UnsupportedFeature` rather than producing a handle that
would fail silently on next launch.

## 6. English only

The architecture supports localisation — all strings live in ARB files from the
first commit — but no translations exist.

## 7. Both native dependencies use Dart native assets

`pdfrx` (PDFium) and `sqlite3` (via drift) build through Dart's newer native
assets / build hooks mechanism rather than classic Flutter plugins. The iOS
build emits a non-fatal `Target native_assets required define SdkRoot but it
was not provided`. Both currently build green on all four platforms including
the Windows runner, but this is the most likely source of future
cross-platform build breakage.

## 8. Encryption is generated, not authored by the app

The RC4 standard-security-handler implementation in `scripts/` exists solely to
produce encrypted test fixtures. The application cannot apply encryption to a
document; it can only read encrypted documents. Authoring encryption is SP-5.

## 9. Test fixtures are generated, not committed

`test_documents/` is gitignored. Run `dart run scripts/make_fixtures.dart`
before any test that needs host-side fixtures. Integration tests build their
own fixtures on-device via the same pure builder, so no test data ships in
release builds.
