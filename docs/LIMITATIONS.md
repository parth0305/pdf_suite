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

Still absent at that point: annotations, signatures, metadata editing,
encryption authoring, redaction, compression, watermarks and OCR. All but
redaction, OCR and compressing foreign documents landed in SP-2b through
SP-5c.

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

Saved annotations can be deleted, restyled, moved and resized, but individual
ink points **cannot be reshaped** — delete and redraw for that. Text markup
cannot be moved at all, because its quads are anchored to the words it covers,
and sticky notes cannot be resized, because every viewer draws the icon at a
fixed size.

Coordinates are written with two decimals, so each move can shift a point by up
to 0.005pt. A hundred moves stays under a single point.

Restyling is offered only for annotations whose geometry Folio can read back:
markup, ink, squares, circles and lines. Any other subtype is delete-only,
because regenerating an appearance for a subtype Folio does not model would
change how another tool's annotation renders.

A protected document has **one password**, which opens it. There is no separate
owner password and no permission flags — printing, copying and editing are not
restricted. Those are advisory in PDF anyway: any viewer may ignore them.

Folio does not **remove** protection from a document, and cannot recover one
whose password is lost.

Watermarks are **text only** and apply to **every page** — there is no image
watermark and no page range. A watermark **cannot be removed** once applied,
because it is page content rather than an annotation; removing it would mean
rewriting content, which needs an object layer Folio does not have.

A watermark drawn as text joins the page's text layer, so search and extraction
find it on every page. That is how most PDF tools behave; avoiding it means
drawing glyph outlines as paths.

Stamps are a **fixed preset set** — Approved, Rejected, Draft, Confidential,
Reviewed, Urgent. There are no custom stamps and no date stamps, and a saved
stamp can be deleted but not restyled: Folio does not reconstruct one well
enough to regenerate its appearance, so Edit annotations lists it as delete
only rather than offering a control that does nothing.

Sticky notes are icons with popups, not text boxes drawn onto the page. A note
that must be readable without tapping is a `/FreeText` annotation, which Folio
does not write.

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

## 4. Scanned documents have no text layer — including the ones Folio makes

A PDF with no text layer yields empty text. That was always true of scanned
documents Folio *opened*. Since SP-6a it is also true of the ones Folio
**creates**: the scanner captures photographs, and a photograph of a page is not
text.

Such a document cannot be searched, and its text cannot be selected or copied.
The scanner screen says so before you save.

**OCR fixes this on iOS, iPadOS and Android** — see §5. It is a separate,
explicit step, so a scan is not searchable until you ask for it.

The `scanned_no_text.pdf` fixture asserts extraction returns empty rather than
failing, and an integration test asserts the same of a fresh scan before OCR
runs, which is what makes that step's effect observable.

## 5. OCR: no Windows, and positions only on Android

Folio's OCR is Tesseract, bundled and run on the device. Three limits follow.

**There is no Windows build.** The binding Folio uses implements Android and
iOS only, and the menu entry is disabled on Windows rather than failing when
tapped. Writing a Windows implementation would mean maintaining a native
Tesseract build that this project has no way to test — see §1.

**Word positions are Android-only.** Tesseract can report each word's box
through hOCR, and Folio uses that on Android to place every word exactly where
it appears, so search highlights land on the word. On iOS the plugin's hOCR
call blocks the platform thread indefinitely — measured, not assumed: a
90-second Dart timeout never fired. iOS therefore uses plain text, and lines
are placed by reading order. The text is fully searchable and copyable; a
highlight shows the right area rather than the exact word. Folio says this in
the UI rather than presenting the two as equivalent.

**English only, and imperfect.** The bundled model is `eng.traineddata` from
Tesseract's `tessdata_fast` set, 3.9MB rather than the 23MB full model. OCR
misreads things — especially poor photographs, unusual fonts and handwriting.
Nothing in Folio treats OCR output as authoritative: it adds a searchable
layer, and never alters the page you can see.

## 6. Compression is lossless only, so scans barely shrink

When most apps say "compress a PDF" they mean downsampling its images and
re-encoding them at lower quality. That is lossy, and Folio does not do it. It
would need a JPEG encoder, which the project has no dependency for —
`dart:ui` decodes anything but encodes only PNG, which is worse than JPEG for
photographs.

What Folio does is exact: identical objects stored once, unreferenced objects
dropped, uncompressed streams deflated. Not one pixel or character changes.

The consequence is that **the documents people most want to shrink shrink the
least**. Measured on real files: a merged set of bank statements gave back 37%,
while a 3.6MB photographed passport scan gave back 632 bytes — 0.0%. Their bytes
are already-compressed JPEG, and nothing lossless can improve on that.

Folio therefore measures first and reports the figure before compressing,
including "nothing worth saving". A button that silently achieves nothing is
worse than one that explains why.

Small documents can even come out **larger**: the rewrite carries its own
overhead — a fresh cross-reference table, a document `/ID` — and on a
three-page file that exceeded what deflating its streams saved, by nine bytes.
Folio reports that as not worth doing rather than growing the file.

## 7. Android open-in-place requires a SAF URI

`PlatformHandles.capture()` on Android accepts only a `content://` URI from the
system picker. A filesystem path cannot be granted a persistable permission, so
it is rejected with `UnsupportedFeature` rather than producing a handle that
would fail silently on next launch.

## 8. English only

The architecture supports localisation — all strings live in ARB files from the
first commit — but no translations exist.

## 9. Both native dependencies use Dart native assets

`pdfrx` (PDFium) and `sqlite3` (via drift) build through Dart's newer native
assets / build hooks mechanism rather than classic Flutter plugins. The iOS
build emits a non-fatal `Target native_assets required define SdkRoot but it
was not provided`. Both currently build green on all four platforms including
the Windows runner, but this is the most likely source of future
cross-platform build breakage.

## 10. Redaction does not cover metadata, bookmarks or attachments

**This is the limitation most likely to hurt someone.** Redaction removes what
is under the boxes from the page. It does not touch `/Title`, `/Author` or
`/Subject`, it does not touch the document outline, and it does not touch
attachments. A document whose title is "Smith settlement draft" still says so
after every occurrence of the name is redacted from the pages.

Folio states this in the confirmation dialog, in an error-coloured panel, rather
than leaving it to be discovered. It is stated here too because a limitation
that only appears in a dialog someone dismissed once is not documented.

## 11. A redacted page becomes an image, and its text is rebuilt

Redaction rasterises the page at 200 DPI and replaces its content with that
image. This is what makes removal unconditional: the original content stream
does not reach the output, so nothing under a box survives — not text, not
vector art, not an image.

The cost is that the page is no longer vector art. It will not stay crisp under
heavy zoom, and it is larger.

The surviving text is then **re-emitted from scratch** as an invisible layer, so
search and selection still work on the rest of the page. That layer is
approximate:

- It uses the non-embedded standard-14 Helvetica. Characters outside
  WinAnsiEncoding — CJK, Devanagari, most emoji — cannot be represented and are
  omitted. They stay visible in the image; they stop being searchable.
- Characters are positioned per run, not per glyph, so selection highlighting
  can sit slightly off the ink.
- Ligatures in the original arrive as whatever PDFium extracted them as.

## 12. A scan is refused unless it is a baseline JPEG

`/DCTDecode`, the PDF filter that carries a JPEG untouched, supports baseline
JPEG. A progressive or arithmetic-coded JPEG renders as garbage in some readers
and not at all in others, so Folio refuses to add one rather than writing a file
that looks fine on the machine that made it.

`image_picker` is asked for `maxWidth` and `imageQuality`, which makes the
platform re-encode to baseline output, so this should not fire in practice. It
is enforced anyway, because "should not happen" is not a guarantee.

That same re-encode is what bakes EXIF orientation into the pixels. PDF ignores
EXIF entirely, so without it a portrait photograph would embed sideways.

## 13. Redaction refuses a shared content stream

If a page being redacted draws a content stream that a page you did **not**
select also draws, there is no correct answer available: dropping it breaks the
other page, and keeping it leaves the redacted text in the file. Folio refuses
the whole operation rather than producing a document that reports success while
still carrying the content.

Sharing a content stream between pages is unusual, so this should be rare.

## 14. Permissions are advisory, and readers disagree about the bits

Folio writes the `/P` bit field a document asks for, and `/Perms` so a reader
can tell it was not tampered with. Nothing beyond that is possible: a
permission is a request a reader may decline, and several readers decline
routinely. The protect dialog says this in the UI rather than implying a
guarantee. The password is the only part that actually protects a document.

Readers also disagree about which bit means what. pdfrx names bit 4
`allowsCopying` and bit 16 `allowsPrinting`, the reverse of ISO 32000-1
Table 22. Folio follows the standard and the integration test compares the raw
integer rather than any reader's named getters, because those names would make
a swapped-bits bug invisible.

Re-protecting a document Folio already protected is not supported: Folio does
not decrypt, so the second pass would encrypt ciphertext. Protect the original
instead.

## 15. Test fixtures are generated, not committed

`test_documents/` is gitignored. Run `dart run scripts/make_fixtures.dart`
before any test that needs host-side fixtures. Integration tests build their
own fixtures on-device via the same pure builder, so no test data ships in
release builds.
