# SP-6a — Scanner (Design)

- **Date:** 2026-08-27
- **Status:** Approved for planning
- **Covers:** Brief phase 9. Phase 10 (OCR) is deliberately deferred; see §7.
- **Depends on:** SP-1 (library, document writer)

---

## 1. What this builds

Capture or import photographs of pages and turn them into a PDF, one page per
image, stored as a new document in the library.

What it does **not** build is a text layer. A scanned document produced by Folio
cannot be searched and its text cannot be selected. That is stated in the
scanner UI, not only in the documentation, because Folio is now the thing
producing such documents rather than merely opening them.

---

## 2. Why DCTDecode, not the raster path SP-5d built

SP-5d writes images as raw RGB under `/FlateDecode`. That is right for a
redacted page, which is a rendering Folio produced at a resolution it chose. It
is wrong here.

A phone photograph is roughly twelve megapixels. As raw RGB that is 36 MB per
page, and photographs deflate barely at all - the output would be tens of
megabytes per scanned page.

PDF has supported JPEG natively since 1.2. `/DCTDecode` means the JPEG bytes go
into the file **untouched**: no decode, no re-encode, no image library, and no
new dependency beyond the picker. A three-page scan stays the size of three
photographs.

### EXIF orientation, and why it is not an afterthought

PDF ignores EXIF entirely. A camera JPEG embedded as-is therefore appears
rotated whenever the phone recorded orientation in EXIF rather than in the pixel
data - which is most of the time on portrait shots.

`image_picker` is asked for `maxWidth` and `imageQuality`, which makes the
platform resize and re-encode the image. The resize **bakes the orientation into
the pixels**, which is the property being relied on here. It is not a
size-reduction measure that happens to help; it is the reason the orientation is
correct.

`kScanMaxWidth = 2000` and `kScanQuality = 85`: enough for a readable A4 page at
roughly 170 DPI, and small enough that a ten-page scan is a few megabytes.

---

## 3. Architecture

```
image_picker  ->  JPEG bytes per page
                        |
                        v
              jpegInfo(bytes)   width, height, components, progressive?
                        |
                        v
        buildScannedDocument(pages)   one page each, /DCTDecode
                        |
                        v
        DocumentWriter.store(bytes, scannedName(...))   a NEW document
```

### Files

| File | Responsibility |
|---|---|
| `lib/domain/scanner/jpeg_info.dart` | Parse a JPEG's SOF marker: dimensions, component count, progressive flag. Pure, no I/O. |
| `lib/domain/scanner/scanned_page.dart` | `ScannedPage`: the JPEG bytes and their parsed info. |
| `lib/domain/scanner/pdf_image_document.dart` | Build a complete PDF from scratch, one `/DCTDecode` page per image. |
| `lib/domain/repositories/scanner_repository.dart` | `save(List<ScannedPage>)`. |
| `lib/data/repositories/scanner_repository_impl.dart` | Builds and stores. |
| `lib/data/scanner/image_source.dart` | Wraps `image_picker` behind an interface, so the repository and its tests never touch the plugin. |
| `lib/features/scanner/scanner_screen.dart` | Capture, import, reorder, remove, save. |

### Why the picker sits behind an interface

`image_picker` needs a real camera and a real gallery. Behind an
`ImageSource` interface the repository is testable with bytes from a fixture,
and the plugin is exercised only by the UI. Without that boundary the entire
scanner would be untestable except by hand.

---

## 4. The JPEG header parser

A JPEG is a sequence of markers. `jpegInfo` walks them to the start-of-frame and
reads:

- **height, width** - needed for the image dictionary and the page size;
- **component count** - 1 means `/DeviceGray`, 3 means `/DeviceRGB`. Writing
  `/DeviceRGB` for a grayscale scan produces a corrupt image, not a grey one;
- **progressive** - SOF2. PDF's `DCTDecode` filter supports **baseline** JPEG.
  A progressive JPEG written into a PDF renders as garbage in some readers and
  not at all in others.

A progressive or unparseable JPEG is refused with `UnsupportedPdfStructure`
before anything is written. `image_picker`'s re-encode produces baseline output,
so this should not fire in practice - which is exactly why it needs a test
rather than trust.

The parser must skip entropy-coded data correctly and must not treat `0xFFD8`
padding bytes as markers. It is pure and fully unit-testable from a handful of
byte sequences.

---

## 5. Page geometry

Each page is the image's aspect ratio fitted inside A4 (595 x 842 pt) and
centred, so a stack of scans prints on ordinary paper without cropping.

An image wider than it is tall produces a landscape fit within the same portrait
page rather than a rotated page: rotating would make a mixed scan alternate
orientation, which is worse to read and worse to print.

The content stream is one `cm` and one `Do`, as in SP-5d.

---

## 6. Testing

### Unit

- `jpegInfo` on a baseline JPEG returns its true dimensions and component count.
- A grayscale JPEG reports 1 component; a mutation to hardcode 3 must fail.
- A progressive JPEG (SOF2) is refused.
- Truncated bytes are refused rather than returning nonsense.
- The built document declares `/DCTDecode`, and `/Length` equals the JPEG's
  byte count exactly - the JPEG is embedded untouched, so any difference means
  it was mangled.
- Page count equals image count, and page order matches input order.
- An empty page list is refused.

### On device

The decisive assertion: build a document from a known JPEG, open it with
PDFium, render page 1, and compare against the same JPEG rendered directly.
This is the only thing that proves `/DCTDecode` was written correctly - the unit
tests can only prove the bytes were copied, not that a reader accepts them.

Also: page count, and that a two-page scan keeps its order.

### Planned mutations

| Mutation | Must fail |
|---|---|
| `/DeviceRGB` hardcoded regardless of component count | the grayscale unit test |
| `/Length` set to something other than the JPEG length | the byte-count test |
| Progressive detection removed | the SOF2 test |
| Page order reversed | the order test |
| `/DCTDecode` replaced with `/FlateDecode` | the device render |

---

## 7. What is deferred, and why it is not hidden

**OCR is not in this slice.** The project brief forbids AI, and every viable
offline OCR engine in 2026 - Tesseract since v4, Apple Vision, Windows OCR - is
neural. Whether those count as "AI OCR" under the brief is a decision for the
project owner, not an implementation detail to settle quietly in a commit.

Until it is settled, a document Folio scans has no text layer. `LIMITATIONS.md`
§4 already records that a PDF without a text layer yields empty search results;
this slice adds that Folio now **creates** such documents, and the scanner
screen says so before the user saves.

---

## 8. Risk, and the probe that retires it

Folio has never written a `/DCTDecode` image. Task 1 of the plan is a throwaway
device probe: build a one-page PDF holding a known JPEG, render it with PDFium,
and check the pixels. No UI, no repository, nothing kept.

If it fails, the fallback is SP-5d's proven `/FlateDecode` raw-RGB path at a
large size cost, which would make `kScanMaxWidth` a much more aggressive number.
Finding that out before the UI exists is the point.

---

## 9. New dependency

`image_picker` (BSD-3-Clause, maintained by the Flutter team). The third
dependency added to this project, after `pointycastle`. It must be recorded in
`docs/THIRD_PARTY_LICENSES.md` or the licence audit test fails.
