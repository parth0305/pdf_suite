# SP-5d Redaction Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redact regions of a PDF by removing the content, not covering it.

**Architecture:** Rasterize each redacted page, paint the boxes into the
pixels, emit the result as an image XObject, and rebuild the surviving text as
invisible text from PDFium's per-character rects. Written through the object
layer's full rewrite so the original content stream never reaches the output.

**Tech Stack:** Flutter/Dart, pdfrx (PDFium), `dart:io` ZLibCodec.

**Spec:** `docs/superpowers/specs/2026-08-27-sp5d-redaction-design.md`

## Global Constraints

- Zero AI, zero paid SDKs, no GPL/LGPL/AGPL, offline-only.
- No new dependencies. The probe confirmed ZLibCodec + raw RGB is sufficient.
- Never destroy an original: output is always a new document.
- Every claim needs a compiled, run, device-verified test.
- Resolution constant: 200 DPI.
- Resource names: `/RdIm0` (image), `/RdF1` (font).

**Task 1 (device probe) is COMPLETE.** PDFium rendered a Flate raw-RGB image
XObject on both iOS and Android, exact colours. Probe deleted as throwaway.

---

### Task 2: RedactionBox and the survivor rule

**Files:**
- Create: `lib/domain/redaction/redaction_box.dart`
- Create: `lib/domain/redaction/redacted_text_layer.dart`
- Test: `test/domain/redaction/redacted_text_layer_test.dart`

**Interfaces:**
- Produces: `RedactionBox({required int pageIndex, required TextRect rect})`;
  `List<int> survivingIndices(PageText text, List<RedactionBox> boxes)`;
  `String invisibleTextStream(PageText text, List<int> keep, ...)`.

- [ ] **Step 1:** Write failing tests: a character wholly inside a box is
      dropped; a character overlapping only the box edge is ALSO dropped
      (intersection, not containment); a character outside every box survives;
      boxes on another page do not affect this one.
- [ ] **Step 2:** Run, confirm failure.
- [ ] **Step 3:** Implement `RedactionBox` and `survivingIndices`.
- [ ] **Step 4:** Run, confirm pass. Mutate `intersects` to `contains`, confirm
      the edge-overlap test fails, restore.
- [ ] **Step 5:** Add `invisibleTextStream`: `BT 3 Tr /RdF1 <size> Tf
      1 0 0 1 <x> <y> Tm (c) Tj ET` per surviving character, escaping `(`, `)`
      and `\`, dropping characters outside WinAnsi.
- [ ] **Step 6:** Test: the stream contains `3 Tr`; a redacted character's
      codepoint appears nowhere in it; a non-WinAnsi character is omitted
      rather than mangled.
- [ ] **Step 7:** Commit.

---

### Task 3: The image XObject

**Files:**
- Create: `lib/domain/redaction/redaction_raster.dart`
- Create: `lib/domain/redaction/pdf_image_object.dart`
- Test: `test/domain/redaction/redaction_raster_test.dart`

**Interfaces:**
- Consumes: `RedactionBox` from Task 2.
- Produces: `List<int> paintBoxes(List<int> bgra, int width, int height,
  List<RedactionBox> boxes, TextRect mediaBox)`;
  `List<int> bgraToRgb(List<int> bgra)`;
  `({String dict, List<int> samples}) imageXObject(int w, int h, List<int> rgb)`.

- [ ] **Step 1:** Failing test: `bgraToRgb` on a known BGRA pixel returns RGB
      in the right order and drops alpha.
- [ ] **Step 2:** Run, confirm failure. Implement. Run, confirm pass.
- [ ] **Step 3:** Mutate to leave the order as BGR; confirm the test fails;
      restore.
- [ ] **Step 4:** Failing test: `paintBoxes` sets every pixel under a box to
      black and leaves a pixel outside it untouched; a box in PDF points maps
      to the right pixel rows given the MediaBox (y is flipped: PDF origin is
      bottom-left, the raster's is top-left).
- [ ] **Step 5:** Implement, run, confirm pass. Mutate to skip the y-flip;
      confirm failure; restore.
- [ ] **Step 6:** Failing test: `imageXObject`'s `/Length` equals the
      compressed sample count, and `/Width` x `/Height` x 3 equals the
      uncompressed count.
- [ ] **Step 7:** Implement, run, confirm pass, commit.

---

### Task 4: The redaction writer

**Files:**
- Create: `lib/domain/redaction/pdf_redaction_writer.dart`
- Modify: `lib/domain/services/edited_name.dart` (add `redactedName`)
- Test: `test/domain/redaction/pdf_redaction_writer_test.dart`

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces: `Uint8List writeRedacted(List<int> original,
  List<RedactionBox> boxes, Map<int, RenderedPage> rasters,
  Map<int, PageText> texts)`.

- [ ] **Step 1:** Failing test: the object number that held the redacted page's
      content stream is absent from the output.
- [ ] **Step 2:** Run, confirm failure.
- [ ] **Step 3:** Implement: build the object list, substitute the page dict,
      OMIT the old content stream objects, append image + content + font.
- [ ] **Step 4:** Run, confirm pass. Mutate to keep the old stream in the list;
      confirm failure; restore.
- [ ] **Step 5:** Failing test: a page with no boxes has its objects passed
      through byte-for-byte.
- [ ] **Step 6:** Failing test: a content stream shared with a non-redacted
      page throws `UnsupportedPdfStructure` with the documented detail.
- [ ] **Step 7:** Implement both, run, confirm pass.
- [ ] **Step 8:** Add `redactedName`, test it alongside `editedName`, commit.

---

### Task 5: Repository and the device assertion

**Files:**
- Create: `lib/domain/repositories/redaction_repository.dart`
- Create: `lib/data/repositories/redaction_repository_impl.dart`
- Test: `integration_test/redaction_flow_test.dart`

**Interfaces:**
- Produces: `Future<LibraryDocument> apply(int documentId,
  List<RedactionBox> boxes)`.

- [ ] **Step 1:** Write the decisive integration test FIRST: redact a box over
      `REDACT-ME-9931` on page 1 of `sample_3page.pdf`, then assert
      (a) `extractText` on the output does not contain it,
      (b) the raw output bytes do not contain it,
      (c) `Confidential` on the same page IS still extractable.
- [ ] **Step 2:** Run on iOS, confirm failure (no repository yet).
- [ ] **Step 3:** Implement the repository: render, extract, write, store.
- [ ] **Step 4:** Run on iOS and Android, confirm pass.
- [ ] **Step 5:** Mutate: emit no invisible text; confirm (c) fails. Restore.
- [ ] **Step 6:** Mutate: skip character dropping; confirm (a) and (b) fail.
      Restore.
- [ ] **Step 7:** Add a test that pages 2 and 3 render pixel-identically to the
      original. Commit.

---

### Task 6: Redact mode in the viewer

**Files:**
- Create: `lib/features/viewer/widgets/redact_overlay.dart`
- Create: `lib/features/viewer/widgets/redact_confirm_dialog.dart`
- Create: `lib/features/viewer/redaction_providers.dart`
- Modify: `lib/features/viewer/viewer_screen.dart` (add `redact` to
  `_ViewerMode`), `lib/main.dart` (provider override),
  `lib/l10n/app_en.arb`
- Test: `test/widgets/redact_confirm_dialog_test.dart`,
  `integration_test/redaction_flow_test.dart` (extend)

- [ ] **Step 1:** Add l10n strings, including the confirmation text naming what
      redaction does NOT cover: metadata, bookmarks, attachments.
- [ ] **Step 2:** Build the overlay: drag to create, reuse SP-3f move/resize.
- [ ] **Step 3:** Build the confirmation dialog. Widget test: the warning about
      metadata is present; confirm returns true only after an explicit tap.
- [ ] **Step 4:** Mutate the dialog to return true without a tap; confirm the
      widget test fails; restore.
- [ ] **Step 5:** Wire the mode into `viewer_screen.dart` and `main.dart`.
- [ ] **Step 6:** Extend the integration test: enter Redact mode, drag a box,
      apply, and assert the resulting document appears in the library.
- [ ] **Step 7:** Run the full aggregate suite on iOS and Android. Commit.

---

### Task 7: Documentation and ship

**Files:**
- Modify: `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/ARCHITECTURE.md`,
  `docs/TESTING.md`, `README.md`

- [ ] **Step 1:** `FEATURES.md`: an SP-5d table.
- [ ] **Step 2:** `LIMITATIONS.md`: all six limitations from spec §6, with
      metadata-is-not-redacted stated first because it is the one that can
      mislead someone into thinking a document is safe to publish.
- [ ] **Step 3:** `ARCHITECTURE.md`: why redaction requires the full rewrite,
      and why the text layer is rebuilt rather than edited.
- [ ] **Step 4:** `TESTING.md`: the raw-bytes assertion — extracting text is
      not enough to prove text is gone.
- [ ] **Step 5:** `README.md`: remove redaction from "not yet possible".
- [ ] **Step 6:** Full unit suite, analyzer, licence audit, both device suites.
- [ ] **Step 7:** Open the PR, wait for all four CI jobs, merge.
