# SP-5d — Redaction (Design)

- **Date:** 2026-08-27
- **Status:** Approved for planning
- **Covers:** Brief phase 13; completes SP-5 (Security + redaction)
- **Depends on:** SP-5a (object layer), SP-3f (move and resize), SP-4a (page geometry)

---

## 1. What redaction has to mean

A black rectangle drawn over a name is not redaction. The text stays in the
content stream, and anyone can select it, copy it, or read it in a text editor.
Every few years a government or a law firm publishes a document redacted that
way and the covered text is recovered within hours.

Folio's redaction removes the bytes. After applying it, the redacted characters
exist nowhere in the output file — not in a content stream, not in an
appearance, not in an earlier revision of the document.

That last clause is the reason this slice sits after SP-5a. Every writer Folio
had before the object layer appends an **incremental update**: the original
bytes stay at the front of the file and the new objects follow. Redacting that
way would leave the original content stream fully intact and trivially
recoverable. Redaction must rewrite the file, and it is the object layer that
makes rewriting possible.

---

## 2. Approach: rasterize, then rebuild the text layer

Three approaches were considered.

| Approach | Removal guarantee | Cost |
|---|---|---|
| Operator surgery — parse the content stream and cut the text-showing operators | Text only. Images and vector art under the box survive. Correctness depends on font encodings, `TJ` kerning arrays and text-matrix accumulation. | A content-stream parser Folio does not have, and a class of bug that looks exactly like success. |
| Rasterize the page | Unconditional. The content stream is gone. | The whole page loses its text layer. |
| **Rasterize, then rebuild the text layer** | **Unconditional, same as rasterizing.** | Page becomes a raster; rebuilt text is per-character standard-14. |

The third is chosen. It gets the removal guarantee of rasterizing without
giving up search and selection on the rest of the page, and it needs no
content-stream parser: the surviving text is **re-emitted from scratch** using
the per-character rectangles PDFium already reports, rather than edited in
place.

The distinction that makes this safe: Folio never tries to *subtract* the
redacted text from something. It throws the entire page away and builds a new
one out of pixels plus the characters it decided to keep.

---

## 3. Architecture

```
RedactionBox (page index + rect in PDF points)
        |
        v
RedactionRepository.apply(documentId, boxes)
        |
        +-- engine.renderPage    -> pixels for each redacted page
        +-- engine.extractText   -> fullText + charRects for each redacted page
        |
        v
buildRedactedObjects(original, boxes, rasters, texts)
        |
        v
writePdfDocument(original, objects)   <- full rewrite, no /Prev
        |
        v
DocumentWriter.store(bytes, redactedName(...))   <- a NEW document
```

### Files

| File | Responsibility |
|---|---|
| `lib/domain/redaction/redaction_box.dart` | `RedactionBox`: page index and a rect in PDF points. Pure data. |
| `lib/domain/redaction/redaction_raster.dart` | Paint boxes into a BGRA buffer; convert BGRA to the RGB samples a PDF image XObject wants. |
| `lib/domain/redaction/redacted_text_layer.dart` | Decide which characters survive; emit the invisible-text content stream. |
| `lib/domain/redaction/pdf_image_object.dart` | The image XObject dictionary and its Flate-compressed samples. |
| `lib/domain/redaction/pdf_redaction_writer.dart` | Assemble the new object list: substitute page content, drop the old stream, add image and font resources. |
| `lib/domain/repositories/redaction_repository.dart` | The interface: `apply(int documentId, List<RedactionBox> boxes)`. |
| `lib/data/repositories/redaction_repository_impl.dart` | Renders, extracts, calls the writer, stores the result. |
| `lib/features/viewer/widgets/redact_overlay.dart` | Drag to create, move and resize pending boxes. |
| `lib/features/viewer/widgets/redact_confirm_dialog.dart` | The confirmation, including what redaction does not cover. |

### Rendering resolution

200 DPI, a single constant in `redaction_raster.dart`. At 200 DPI an A4 page is
1654 x 2339 px; the raw RGB samples are 11.6 MB and deflate to a few hundred
kilobytes for typical text pages. 300 DPI more than doubles that for a
difference few readers would notice on a page that is already a raster.

### The new content stream

```
q
<width> 0 0 <height> <x0> <y0> cm
/RdIm0 Do
Q
BT 3 Tr /RdF1 <size> Tf 1 0 0 1 <x> <y> Tm (c) Tj ET     <- one per surviving character
...
```

The image is scaled to the page's `/MediaBox`, resolved through inheritance by
the existing `mediaBoxOf` in `lib/domain/watermark/page_geometry.dart`. `3 Tr`
is text render mode 3: no fill, no stroke, invisible — but extractable and
searchable.

### Object substitution

`parsePdfObjects` gives every object in the original. The writer returns a new
list in which, for each redacted page:

- the page dictionary is replaced, with `/Contents` pointing at the new stream
  and `/Resources` carrying `/XObject << /RdIm0 n 0 R >>` and
  `/Font << /RdF1 n 0 R >>`;
- the objects that were the page's old content streams are **omitted from the
  list entirely**, so they are absent from the output rather than orphaned
  inside it;
- the image XObject, the new content stream and one shared Helvetica font
  object are appended.

Pages with no boxes are not touched: their objects pass through byte-for-byte.

### The shared-content-stream case

If a redacted page's content stream object is also referenced by a page the
user did not select, there is no correct answer available: dropping it breaks
the other page, and keeping it leaves the redacted text in the file. Folio
refuses, with `UnsupportedPdfStructure` and the detail
`content stream shared with a page that was not redacted`.

This is rare, and refusing is the only honest option. A partial redaction that
reports success is the failure mode this whole slice exists to prevent.

---

## 4. Which characters survive

`PageText.charRects[i]` locates `fullText[i]`, one entry per code unit. A
character is discarded when its rect **intersects** any box on that page —
not when it is contained by one. A character half-covered by a box is a
character the user meant to remove, and half a glyph is often enough to read.

Intersection is computed in PDF points, the same space the boxes are stored in.

Surviving characters are emitted with `Tm` positioning them at their original
rect origin, at a font size taken from the rect height. Word and line structure
is not reconstructed: extraction returns the characters in their original
order, which is what search needs.

### Encoding

The font is the non-embedded standard-14 Helvetica already used by stamps
(`helveticaFontObject()`), with WinAnsiEncoding. Characters outside WinAnsi —
CJK, Devanagari, most emoji — cannot be represented and are **dropped from the
rebuilt text layer**. They remain visible in the raster; they are simply not
searchable afterwards.

This is a real loss and is documented as one. It is not a removal failure: a
dropped character is a character that is *more* gone, not less.

---

## 5. User flow

Redact becomes a viewer mode alongside markup, draw, signature, note and stamp.

1. The user enters Redact mode and drags a rectangle over the content.
2. Boxes render as solid black with a visible border, and can be moved and
   resized with the SP-3f machinery until committed.
3. **Apply redactions** opens a confirmation that states plainly: the result is
   a new document, the redacted content cannot be recovered from it, the page
   becomes an image, and **document metadata, bookmarks and attachments are not
   redacted**.
4. On confirm, the repository produces a new document named by
   `redactedName(...)`, a new function added alongside the existing
   `editedName` and `extractedName` in `lib/domain/services/edited_name.dart`
   and following their naming convention.

Nothing is written before the confirmation. Discarding pending boxes follows
the existing unsaved-annotation discard prompt.

---

## 6. Limitations, to be written into `LIMITATIONS.md`

1. **Metadata is not redacted.** A name in `/Title`, `/Author` or `/Subject`
   survives. Folio says so in the confirmation dialog.
2. **Bookmarks and attachments are not redacted.** An outline entry naming a
   redacted section survives.
3. **The redacted page becomes a raster** at 200 DPI. Vector text is no longer
   crisp under heavy zoom, and the page grows.
4. **Rebuilt text is per-character standard-14.** Ligatures are separated,
   complex scripts lose shaping, and non-WinAnsi characters leave the text
   layer.
5. **A shared content stream is refused,** as described in §3.
6. **Only what is under a box is removed.** Redaction cannot infer that a
   redacted name also appears elsewhere on the page.

---

## 7. Testing

### The decisive assertion, on device

Redact a box over a known word, then:

- `engine.extractText` on the output must not contain that word;
- the raw output **bytes** must not contain it either, which is what catches a
  redaction that only hid the text;
- a different word on the same page, outside every box, **must** still be
  extractable — without this the rebuild half could silently emit nothing and
  every removal assertion would still pass.

### Unit level

- Intersection, not containment: a character overlapping a box's edge is
  dropped. A mutation to `contains` must fail.
- The old content stream object number is absent from the output.
- Pages without boxes are byte-identical to their originals.
- BGRA to RGB conversion drops alpha and reorders channels; a mutation that
  leaves the order as BGR must fail against a known colour.
- The image dictionary's `/Length` describes the compressed samples, and
  `/Width` x `/Height` x 3 equals the uncompressed sample count.

### Planned mutations

| Mutation | Must fail |
|---|---|
| Skip the character-dropping step entirely | The extract-and-grep assertion |
| `contains` instead of `intersects` | The edge-overlap unit test |
| Keep the old content stream in the object list | The raw-bytes assertion |
| Emit no invisible text at all | The surviving-word assertion |
| Swap R and B channels | The colour unit test |

### Test fixture

`sample_3page.pdf` page 1 already carries both halves of the assertion:

- title `Confidential Invoice`
- body `Acme Corporation - Total due: 48500 rupees - REDACT-ME-9931`

`REDACT-ME-9931` is the target — a token that appears nowhere else, so a
raw-byte search for it in the output is unambiguous. `Confidential` is the
survivor, on the same page and outside the box, and it is already relied on by
the watermark and object-layer suites, so a regression there would be caught
twice.

---

## 8. Risk, and the probe that retires it

The design rests on PDFium rendering a Flate-compressed raw-RGB image XObject
that Folio wrote. Folio has never written an image XObject of any kind.

**Task 1 of the implementation plan is a throwaway device probe of exactly
that** — build a one-page PDF whose only content is such an image, render it
with PDFium, and compare against the source pixels. No UI, no repository, no
tests kept.

If it fails, the fallback is to encode the raster as PNG through
`dart:ui`'s `Image.toByteData(format: ImageByteFormat.png)` and use the PNG's
own deflate stream, or to reconsider the resolution and colour space. The
fallback is cheap; discovering the problem after the UI is built is not.
