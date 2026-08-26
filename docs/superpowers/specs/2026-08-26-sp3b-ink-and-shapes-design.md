# SP-3b — Ink and Shapes (Design)

- **Date:** 2026-08-26
- **Status:** Approved for planning
- **Covers:** the drawing portion of brief Phase 6
- **Depends on:** SP-3a (annotation write path), SP-2b (metadata preservation)

---

## 1. Scope

**Freehand pen, rectangle, oval, line and arrow**, written into the PDF as
`/Ink`, `/Square`, `/Circle` and `/Line` annotations through the write path
SP-3a proved. Note that PDF's `/Circle` draws an ellipse, not a circle — see
§5.

All five ship together. Once freehand ink works, the geometric shapes are
*simpler* — a drag defines a bounding box rather than a path — and they share
the same appearance-stream generation. Slicing further would be over-slicing.

### Explicitly not in this slice

Sticky notes, text annotations and stamps (SP-3c). Editing, moving, restyling or
deleting an annotation **after** it has been saved — that needs reading
`/Annots` back, which is its own sub-project (§8).

---

## 2. Why this matters now

**You currently cannot annotate a scanned document at all.** SP-3a's markup
attaches to selected text, and a scan has none. Every fixture in
`test_documents/scanned_no_text.pdf` is untouchable today.

Drawing is also the only annotation type that works regardless of what a page
contains, which makes it the widest-reach addition remaining.

---

## 3. What already exists and is not rebuilt

SP-3a shipped and merged the entire write path:

| Component | Reused as-is |
|---|---|
| `PdfObjectReader` | overrides the page dictionary to carry `/Annots` |
| `pdf_annotation_writer` | incremental update, xref, chained trailer |
| `pdf_appearance` | `/AP` form XObjects |
| `DocumentWriter` | single library write path, metadata preserved |
| `AnnotationRepository` | save → new document, source byte-identical |

Verified on both platforms by rendering the page before and after and requiring
the pixels to differ. SP-3b adds annotation *types*, not a new pipeline.

---

## 4. The one genuinely new problem: coordinates

Text markup received its geometry free — `charRects` are already PDF user space,
y-up. Drawing does not. A finger at a canvas position must become a PDF point:

```
normalised = (canvasPoint - pageRect.topLeft) / pageRect.size
pdfX       = normalised.dx * page.width
pdfY       = (1 - normalised.dy) * page.height      // y-up flip
```

`pageRect` is supplied by pdfrx's page paint callback,
`void Function(Canvas, Rect pageRect, PdfPage page)`, and is cached per page as
it fires.

This is a **pure function with an obvious inverse**, so it is tested by round
trip: canvas → PDF → canvas must return the original point, at several zoom
levels and on a rotated page. Getting the flip wrong would place every stroke
upside down, and would look plausible until someone opened the file.

**This is the first task**, before any drawing UI exists.

---

## 5. Data model

`AnnotationSession` currently holds `List<TextMarkup>`. It becomes generic over
a sealed supertype:

```dart
/// A point in PDF user space, y-up. New in this slice: SP-3a only ever needed
/// rectangles, so no point type existed.
class PdfPoint {
  const PdfPoint(this.x, this.y);
  final double x;
  final double y;
}

sealed class Annotation {
  int get pageIndex;
  String get pdfSubtype;
}

final class TextMarkup extends Annotation { ... }   // SP-3a, unchanged behaviour

final class DrawingAnnotation extends Annotation {
  final DrawingKind kind;
  final int pageIndex;
  /// PDF user space, y-up. For ink, the smoothed path; for shapes, two corners
  /// of the drag.
  final List<PdfPoint> points;
  final int colorArgb;
  final double strokeWidth;
}

enum DrawingKind { ink, rectangle, ellipse, line, arrow }
```

### A naming trap worth pinning down

PDF's `/Circle` annotation does **not** draw a circle: it draws an **ellipse
inscribed in its `/Rect`**. Three names are therefore in play, and conflating
them produces either a wrong subtype or a surprised user:

| Layer | Name |
|---|---|
| `DrawingKind` | `ellipse` — what it actually draws |
| PDF subtype | `/Circle` — what the format calls it |
| User-facing label | "Oval" — what a user recognises |

`TextMarkup` also becomes `final class TextMarkup extends Annotation`; it is
currently a plain class. Its behaviour and tests are unchanged.

One session, one undo stack, one Save. A user can highlight *and* draw before
saving once.

The alternative — a parallel drawing session — was rejected: it produces two
undo stacks, two Save buttons, and a user who does both ends up with two
documents.

---

## 6. Appearance streams

Every drawing gets an `/AP`, for the same reason SP-3a does: PDFium tolerates
their absence, other viewers were never measurable here, and portability is the
whole reason annotations are written into the file.

| Kind | Content stream |
|---|---|
| Ink | `m` then a run of `c` curves through the smoothed path, `S` |
| Rectangle | `re`, `S` |
| Ellipse (`/Circle`) | four Bézier arcs approximating the ellipse, `S` |
| Line | `m`, `l`, `S` |
| Arrow | line plus two stroked segments for the head |

`/Square` and `/Circle` annotations use `/Rect` for geometry. `/Ink` uses
`/InkList`, an array of arrays of alternating x y coordinates. `/Line` uses
`/L [x1 y1 x2 y2]`.

---

## 7. Known risk: smoothing

Raw touch samples produce visibly jagged strokes, and the naive fix — emitting
every sample as a line segment — produces both ugly output and enormous
`/InkList` arrays.

The approach is standard: drop samples closer than a minimum distance, then fit
a Catmull-Rom spline through the survivors and emit it as cubic Béziers.

**This gets its own task with visual verification**, not an assumption that raw
points look acceptable. It affects both the on-screen preview and the emitted
path data, so preview and output must be generated from the same smoothed
points or they will disagree.

---

## 8. What this deliberately leaves broken

**A saved drawing cannot be edited or deleted**, exactly as with SP-3a markup.
Staged drawings can be undone before saving; once written, they are permanent.

This is worth stating plainly because it will feel like a defect. Fixing it
requires enumerating `/Annots`, hit-testing against annotation geometry, and
removing objects — which means growing `PdfObjectReader` past page dictionaries,
something its own spec says should trigger a scope rethink rather than quiet
growth. It is a separate sub-project with its own evidence.

Checked 2026-08-26: pdfrx's `PdfAnnotation` is metadata-only — title, content,
subject, dates, derived from links. It exposes no geometry, no subtype and no
enumeration, so this cannot be borrowed from the engine.

---

## 9. Data safety

Inherited unchanged from SP-3a, with no new work:

- output through `SafeFileWriter`; saving creates a **new** library document
- the source is byte-identical afterwards, asserted by SHA-256
- metadata preserved, because saving goes through `DocumentWriter`
- cross-reference-stream documents refused with `UnsupportedPdfStructure`

---

## 10. Testing

### Unit — no simulator

- **coordinate mapping**: round trip at 1x, 2.5x and 0.4x zoom; on a page
  scrolled partly out of view; on a 90°-rotated page; and the explicit
  assertion that a point near the page *top* maps to a **large** PDF y
- **smoothing**: samples closer than the minimum distance are dropped; a
  straight drag stays straight; a curve keeps its endpoints exactly
- **`/InkList` emission**: alternating x y, one array per stroke
- **shape geometry**: a drag in any of the four directions produces the same
  normalised rectangle
- **`/Circle` is an ellipse**: a non-square drag produces an oval, not a circle
- **session**: text markup and drawings coexist, undo crosses both types

### Integration — device

- draw a stroke, save, reopen, **assert it renders** by pixel comparison
- each shape kind renders
- **draw on `scanned_no_text.pdf`** — the case impossible before this slice
- the source document is byte-identical afterwards
- a highlight and a drawing saved together produce one document containing both
- metadata survives, so SP-2b has not regressed

---

## 11. Definition of done

- [ ] Pen, rectangle, oval, line and arrow create, undo and save
- [ ] Saved drawings **render** on reopen, verified by pixel comparison
- [ ] Drawing works on a scanned page with no text layer
- [ ] Source documents byte-identical after every save
- [ ] Text markup and drawings share one session, undo stack and Save
- [ ] `PdfEngine` still has no write method
- [ ] `lib/domain/annotations` unit coverage ≥90%
- [ ] Integration passes on iOS simulator **and** Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] CI green on all four jobs including `build-windows`
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md`, `TESTING.md` updated

---

## 12. Next

SP-3c — sticky notes and stamps — and separately, editing or deleting saved
annotations, which needs reading `/Annots` back and should be scoped on its own
evidence rather than bundled here.
