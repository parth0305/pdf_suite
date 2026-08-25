# SP-3a — Text Markup Annotations (Design)

- **Date:** 2026-08-25
- **Status:** Approved for planning
- **Covers:** the text-markup portion of brief Phase 6
- **Depends on:** SP-1 (text geometry), SP-2a (staged editing pattern), SP-2b (metadata preservation)

---

## 1. Scope

**Highlight, underline and strikethrough** applied to selected text, written into
the PDF as real annotation objects.

### Explicitly not in this slice

Freehand ink, rectangles, circles, arrows, lines, sticky notes, text annotations
and stamps. Also: moving, resizing and restyling an annotation after it has been
saved. Those are SP-3b and SP-3c.

Phase 6 was sliced rather than built whole because bundling has already gone
wrong twice on this project — the original SP-2 bundle, and then SP-2b's
"object layer" scope, both of which collapsed once probed.

---

## 2. Why this slice first

Text markup reuses geometry SP-1 already proved. `PageText.charRects` holds one
rectangle per code unit of `fullText`, in PDF user space with y-up coordinates —
verified on device, and asserted by a test that would fail if the alignment
broke. Those rectangles convert to `/QuadPoints` almost directly.

It is also the most-used annotation type, and it exercises the entire write path
end to end, so SP-3b and SP-3c inherit a proven pipeline.

---

## 3. Feasibility, already established

A spike on 2026-08-25 confirmed that an annotation can be attached by **PDF
incremental update**, and that PDFium genuinely parses it:

| Measurement | Result |
|---|---|
| PDFium reopens the patched file | yes |
| Page count preserved | yes |
| Pixels changed by the annotation | 26,969 (5.3%) — it **rendered** |
| Page text still extractable | yes |
| Overhead | 390 bytes |

Rendering is the meaningful part. A file that merely opens proves only that it
is not corrupt; a file whose annotation is drawn proves the annotation was
parsed.

### What the spike also revealed

Unlike `/Info`, an annotation cannot be a pure addition. The **page dictionary
must be overridden** to carry `/Annots`, which means reading and re-emitting an
existing object. The spike did this with a regular expression, and that is not
good enough to ship: it breaks on nested dictionaries, on pages where
`/Type /Page` is not the first key, and on pages that already have an `/Annots`
array to merge into rather than replace.

That gap is what `PdfObjectReader` (§6) exists to close.

---

## 4. Storage decision: annotations go into the PDF

Annotations are written as real PDF objects, not stored in Folio's database and
drawn as an overlay.

The alternative would have been markedly simpler — a row in SQLite, painted over
the rendered page, with trivial editing and no PDF writing at all. It was
rejected because those annotations would be **invisible outside Folio**. A user
who highlights a contract and emails it expects the recipient to see the
highlights. An annotation feature whose output only exists inside one app is
surprising in a way that no amount of documentation fixes.

The cost is accepted deliberately: a minimal object parser, and a file rewrite
per save.

---

## 5. Architecture

Mirrors SP-2a, because the same three properties are wanted.

```
AnnotationSession        pending markups, undo/redo — pure Dart, no native
        │
        │  Save
        ▼
PdfAnnotationWriter      incremental update → new library document
```

1. **Undo is a stack of in-memory snapshots**, not a history of file writes.
2. **The logic unit-tests with no simulator**, as `PageEditSession` does.
3. **Nothing is written until the user saves**, so an abandoned session leaves
   no partial files.

### Rendering is free

PDFium renders annotations itself — `PdfAnnotationRenderingMode.annotationAndForms`
is the default for page rendering. Once written, markup simply appears in the
viewer. Folio does **not** need an overlay layer for saved annotations.

Pending (unsaved) markup is a different matter: it does not exist in the file
yet, so it is drawn as an overlay using the same `pagePaintCallbacks` mechanism
SP-1 already uses for search highlighting.

---

## 6. The one genuinely new component

`PdfObjectReader` — a minimal PDF dictionary reader and re-emitter, roughly 300
lines. It must:

- parse a dictionary with **nested** `<<…>>` correctly
- locate a page object regardless of key order
- read an existing `/Annots` array and **merge** into it rather than replace it
- re-emit the dictionary with an added or extended `/Annots`

This is the smallest honest form of "the object layer". It is not a general PDF
parser, and it should not become one: it handles page dictionaries, and the
moment something needs more, that is a signal to reconsider scope rather than
grow this file.

**Constraint carried from SP-2b:** the incremental-update technique assumes a
classic cross-reference table, which is what Folio's own writer emits. It is
therefore applied only to documents Folio produced or imported and re-saved.
PDF 1.5+ cross-reference streams are out of scope and must be detected and
refused rather than silently mishandled.

---

## 7. Appearance streams — probed, partially answered

**PDFium renders `/Highlight` without an `/AP`.** Probed 2026-08-25: a highlight
built from `charRects` quads, with no appearance stream, changed 1090 pixels in
the rendered page, positioned over the intended text. The quad coordinates came
straight from SP-1's `charRects` with no conversion, confirming that geometry
feeds directly into `/QuadPoints`.

**Whether other viewers do the same is still unknown, and could not be measured
on this machine.**

An attempt to check macOS PDFKit via QuickLook returned "renders identically",
which looked like a finding and was not one. Validating the instrument first — by
feeding it a large opaque red square that PDFium definitely renders — produced
byte-identical output too. **QuickLook ignores annotations entirely**, so the
test measured nothing. Recorded here because a null result from a broken
instrument is more dangerous than no result at all.

### Decision: generate `/AP` anyway

Portability is the entire justification for writing annotations into the PDF
(§4). An annotation that renders only in Folio would defeat that reason while
paying its whole cost.

Since PDFium's tolerance cannot be generalised to Acrobat, Preview, Chrome or
mobile viewers, the writer generates appearance streams. It is more work, and it
is the only choice consistent with why this design was chosen.

`/AP` generation for markup is modest: a form XObject per annotation containing
one filled quad per rectangle, using `/Multiply` blend for highlight and a
stroked line for underline and strikethrough.

---

## 8. Data model

```dart
enum MarkupKind { highlight, underline, strikeOut }

class TextMarkup {
  final MarkupKind kind;
  final int pageIndex;

  /// PDF user space, y-up — the same space charRects use, so no conversion.
  final List<TextRect> quads;

  /// sRGB, written as PDF /C [r g b] with components in 0..1.
  final int colorArgb;
}
```

`AnnotationSession` holds `List<TextMarkup>` plus a command stack, exposing
`add`, `removeAt`, `undo`, `redo`, `isDirty` and `isEmpty` — deliberately the
same shape as `PageEditSession`, so the two read alike.

---

## 9. Data safety

Unchanged from SP-1 and SP-2a, and it applies without new work:

- output written through `SafeFileWriter` — temp file, validate, atomic rename
- saving produces a **new library document**; the source is byte-identical

### One refactor this slice requires

Metadata preservation currently lives inside
`PageOperationsRepositoryImpl._store`, which is private to page operations.
Annotations are not a page operation, so they would either duplicate that logic
or silently lose metadata again — reintroducing the exact bug SP-2b fixed.

So `_store` is extracted into a shared collaborator:

```dart
class DocumentWriter {
  /// Writes bytes into the library as a new content-addressed document,
  /// re-attaching [metadata] first. The single place any produced document
  /// enters the library.
  Future<LibraryDocument> store(
    Uint8List bytes,
    String displayName, {
    PdfMetadata? metadata,
  });
}
```

Both `PageOperationsRepositoryImpl` and the new annotation repository depend on
it. This is a targeted improvement to code being worked in, not unrelated
refactoring: without it, the second caller is where metadata loss returns.

---

## 10. Error handling

Reuses the existing `AppFailure` hierarchy. One new variant:

| Failure | Raised when |
|---|---|
| `UnsupportedPdfStructure` | the document uses cross-reference streams, so an incremental update cannot be applied safely |

It maps to a localized message through the exhaustive `switch`, which means
adding it without copy is a compile error — the property verified by mutation in
SP-1 and exercised again in SP-2a.

Refusing loudly is the point: silently producing a document whose annotations do
not appear would be worse than declining.

---

## 11. Testing

### Unit — no simulator

- `DocumentWriter`: metadata re-attached, original untouched, and a regression
  test that a document saved through the **annotation** path keeps its metadata
- `AnnotationSession`: add, remove, undo past the beginning, redo past the end,
  a new edit discarding the redo branch, `isDirty` after add-then-undo
- `PdfObjectReader`: nested dictionaries, `/Type /Page` not first, an existing
  `/Annots` array merged rather than replaced, malformed input rejected
- `TextMarkup` → `/QuadPoints`: correct ordering and y-up preservation
- `/AP` form XObject generation: one filled quad per rectangle, correct blend
  mode per markup kind
- cross-reference-stream documents detected and refused

### Integration — device

- highlight selected text, save, **reopen and confirm the annotation renders**
  by pixel comparison, the same check the spike used
- the source document is byte-identical afterwards, by SHA-256
- extracted text is unchanged — markup must not disturb content
- metadata still survives, so SP-2b has not regressed
- a page that already has annotations keeps them and gains the new one

---

## 12. Definition of done

- [ ] Highlight, underline and strikethrough create, undo and save
- [ ] Saved annotations render on reopen, verified by pixel comparison
- [ ] Source documents byte-identical after every save
- [ ] Cross-reference-stream documents refused with a clear message
- [ ] `PdfEngine` still has no write method
- [ ] `domain/annotations` unit coverage ≥90%
- [ ] Integration passes on iOS simulator **and** Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] CI green on all four jobs including `build-windows`
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md` updated

---

## 13. Next

SP-3b — freehand ink and shapes — which needs a drawing surface but inherits
this write path. SP-3c — sticky notes and stamps. Neither should be scoped until
this one ships.
