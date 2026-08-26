# SP-3d — Signatures

**Status:** approved, ready for planning
**Date:** 2026-08-26
**Depends on:** SP-3b (ink and shapes), SP-3c (editing saved annotations).

## Problem

Signing is the single most common reason someone opens a PDF on a phone, and
Folio cannot do it. Drawing a signature freehand every time is possible today
with the pen tool, but nobody wants to redraw their signature on every
document — and a signature drawn at page scale with a fingertip looks nothing
like a signature.

## Scope

**In:** draw a signature once, save it with a label, and place it on any
document by dragging a box. Several signatures, managed where you sign.

**Out, deliberately:**

- **Photographed signatures.** Scoped as a later slice. The storage format
  carries a `kind` discriminator and a nullable image column so that slice
  needs no migration, but nothing in this one reads them.
- **Cryptographic signing.** An entirely different problem — certificates, key
  storage, trust chains — and not what "sign a PDF" means to most people.
- **Flattening.** A placed signature stays a real annotation. Burning
  annotations into page content is its own feature and destroys editability.

## Decisions

### A placed signature is an `/Ink` annotation

It *is* ink, so that is the honest representation. It also means the signature
inherits SP-3c's delete and restyle for nothing, renders in every viewer that
reads annotations, and leaves the original page content untouched.

### Aspect ratio is preserved

The signature is fitted inside the drag box and centred, never stretched to
fill it. A stretched signature looks forged.

### Ink carries multiple strokes

This is the load-bearing change, and it is a correction as much as a feature.

`DrawingAnnotation.points` is a single polyline. A signature is several
disconnected strokes, so placing one today would draw straight lines through
every gap. PDF's `/InkList` is **defined** as an array of stroke arrays; SP-3b
simply never emitted more than one.

Geometry therefore becomes `strokes: List<List<PdfPoint>>`, with `points` kept
as a getter returning `strokes.first` so shape code is untouched.

**This also fixes a live defect in SP-3c.** `PdfAnnotationReader` flattens
`/InkList` into one point list, so restyling a multi-stroke ink annotation
written by another tool regenerates its appearance with the strokes joined.
Probed on 2026-08-26: `/InkList [[10 10 20 20] [80 80 90 90]]` read back as one
four-point path, which would draw a line from (20,20) to (80,80) that does not
exist in the document. The geometry is copied verbatim so the file is not
corrupted, but it renders visibly wrong. Fixed here, with a regression test.

### Strokes are stored normalised, y-up

A saved signature holds its strokes in a unit box with y increasing upward —
the same orientation as PDF user space, so placement is a multiply and an
offset with no flip. Getting a flip wrong here would put every signature
upside down, and normalisation is what makes one saved signature usable at any
size on any page.

## Architecture

### Storage

A new drift table, schema v4:

| Column | Purpose |
|---|---|
| `id` | primary key |
| `label` | user-visible name, e.g. "Full" or "Initials" |
| `kind` | `drawn` today; the discriminator a photographed signature needs |
| `strokes` | JSON: `[[{x,y},…],…]`, normalised to a unit box, y-up |
| `aspectRatio` | width ÷ height as drawn, so placement can preserve it |
| `imageBytes` | nullable, unused in this slice |
| `createdAt` | ordering |

```dart
class SavedSignature {
  final int id;
  final String label;
  final List<List<PdfPoint>> strokes;   // unit box, y-up
  final double aspectRatio;
}
```

### `lib/domain/signatures/signature_geometry.dart` — new

Two pure functions, tested directly rather than only through the UI:

```dart
/// Normalises captured strokes into a unit box, y-up, and reports the aspect
/// ratio they were drawn at.
({List<List<PdfPoint>> strokes, double aspectRatio}) normaliseStrokes(
  List<List<PdfPoint>> captured,
);

/// Fits [signature] inside [box] preserving its aspect ratio, centred.
List<List<PdfPoint>> placeSignature(
  SavedSignature signature, {
  required TextRect box,
});
```

### Changes to existing files

- `drawing_annotation.dart` — `strokes` replaces `points` as the stored
  geometry; `points` becomes `strokes.first`. **`boundsPt` must span every
  stroke**: it currently iterates `points`, which with multiple strokes would
  bound only the first, giving a wrong `/Rect` and a `/BBox` that clips most of
  the signature away.
- `drawing_surface.dart` — the staged-drawing preview paints `points`; for ink
  it must paint every stroke, or a placed signature previews as its first
  stroke alone.
- `drawing_appearance.dart` — one `m` … `c` … subpath per stroke, still a
  single `S`.
- `pdf_annotation_writer.dart` — `/InkList` emits one array per stroke.
- `pdf_annotation_reader.dart` — parses `/InkList` sub-arrays instead of
  flattening them.

### UI

- `SignatureSheet` — lists saved signatures, each previewed by `CustomPaint`
  from its own strokes, so there are no thumbnail files to keep in sync. Add,
  rename, delete.
- `SignatureCaptureCanvas` — a drawing surface reusing SP-3b's `thinSamples`;
  Clear and Save.
- `SignaturePlacementSurface` — an overlay present only in signature mode, so
  it cannot compete with the viewer for scroll or pinch. Drag defines the box;
  a live preview shows the fitted signature; release stages **one**
  `DrawingAnnotation`.

Saving goes through `AnnotationRepository.saveAnnotations` unchanged. This
slice adds nothing to the write path.

## Risks

**The multi-stroke change touches shipped code.** SP-3b's tests are the guard:
they must stay green throughout, and a mutation that re-flattens strokes must
turn them red.

**Schema v4 migration.** Additive only — a new table, no changes to existing
ones.

**A signature drawn in a small canvas and placed large will show its
sampling.** `thinSamples` keeps points 2pt apart in canvas space; scaled up,
that becomes visible faceting. Mitigated by capturing in as large a canvas as
the sheet allows and by the existing Catmull-Rom smoothing, which interpolates
rather than joining points with straight lines.

## Testing

Unit:

- `normaliseStrokes`: output within the unit box; aspect ratio for a wide and a
  tall capture; a single-point stroke does not divide by zero.
- `placeSignature`: fits inside the box; centred; aspect preserved for both a
  box wider than the signature and one taller; y-up is not flipped.
- `boundsPt` spans every stroke, not just the first.
- `/InkList` emits one array per stroke; the appearance stream contains N `m`
  operators for N strokes.
- The reader preserves sub-paths — the SP-3c regression test.
- Every SP-3b test still passes.

Integration, all verified by rendering:

- a placed signature draws;
- a **two-stroke** signature draws with a gap between strokes — the assertion
  that catches joining;
- deleting a placed signature removes it entirely, not one stroke;
- the source document stays byte-identical.

Mutations: flatten strokes back into one path; drop aspect preservation; bound
only the first stroke.

The 18 existing uses of `.points` across the codebase are why `points` survives
as a getter: only the ink-specific sites — the writer's `/InkList`, the ink
case of the appearance generator, the preview painter, and `boundsPt` — need to
change at all.

## Definition of done

- [ ] Draw, label, save, rename and delete signatures
- [ ] Place a saved signature by dragging a box, aspect preserved
- [ ] A placed signature is one annotation and deletes as one
- [ ] Multi-stroke ink round-trips without joining, proven by mutation
- [ ] Every SP-3b and SP-3c test still passes
- [ ] `PdfEngine` still has no write method
- [ ] Integration green on iOS simulator and Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] All four CI jobs green, `build-windows` included
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md`, `TESTING.md` updated
