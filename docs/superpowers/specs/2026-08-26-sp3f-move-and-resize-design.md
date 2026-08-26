# SP-3f — Moving and resizing annotations

**Status:** approved, ready for planning
**Date:** 2026-08-26
**Depends on:** SP-3b, SP-3c, SP-3d, SP-3e.

## Problem

An annotation placed slightly wrong cannot be nudged. A stamp dropped in the
wrong corner, a rectangle a little too small, a signature that landed above the
line rather than on it — all of them can only be deleted and redone.

SP-3c deferred this deliberately. This slice closes it.

## Probed before designing

PDF §12.5.5 says a viewer maps an annotation's appearance `/BBox` onto its
`/Rect`. Whether PDFium actually does was measured on device, 2026-08-26:

| Probe | Result |
|---|---|
| Change `/Rect` only | mark moved, columns 20..59 → 200..239 |
| Enlarge `/Rect` | mark scaled, 40 → 120 columns |
| `/BBox` in page coordinates, as Folio's drawings use | still moved, 20..59 → 200..239 |

So moving and resizing needs **no appearance regeneration at all**. That is the
finding this slice is built on, and it is why it stays small.

## Scope

**In:** move any annotation except text markup; resize everything except notes
and markup; both inside the existing Edit-annotations mode.

**Out, deliberately:**

- **Moving text markup.** `/QuadPoints` are anchored to the words they cover.
  A highlight dragged off its text is meaningless.
- **Resizing sticky notes.** A `/Text` icon is drawn at a fixed size by every
  viewer, so there is nothing for a resize to change.
- **Rotation.** No annotation Folio writes has a rotated form, and adding one
  would mean carrying a `/Matrix` through the geometry transform.
- **Higher-precision coordinate output.** See the accuracy note below.

## Decisions

### A move is a `/Rect` rewrite plus one affine over the geometry

The session stages a **target rect** per object number. Applying it rewrites
`/Rect`, then transforms every coordinate-pair geometry key by the same affine
mapping the old rect onto the new one:

```
scaleX = (new.right - new.left) / (old.right - old.left)
x'     = new.left + (x - old.left) * scaleX
```

and likewise for y.

`/InkList`, `/L` and `/QuadPoints` are all flat lists of x-y pairs, so **one
generic function handles them without reconstructing the annotation**. That
matters: it means a stamp can move even though SP-3e leaves it delete-only for
restyling, because moving needs no understanding of what the annotation is.

### Geometry is rewritten, and that is a stated exception

SP-3c established that a restyle copies geometry verbatim, because a restyle
that moved something would corrupt a document invisibly. That rule stands.

A move is the one operation that *is* a request to change geometry, so it
rewrites it — and rewrites `/Rect` and the geometry together, so they never
disagree.

**Rewriting `/Rect` alone would be a silent trap.** Rendering would follow the
appearance and look right, but the geometry keys would still point at the old
position: a later restyle regenerates the appearance from geometry and the
annotation jumps back. Two actions apart, and invisible in between.

### Accuracy

Coordinates are re-emitted through `pdfNumber`, which formats to two decimals,
so each move can shift a point by up to 0.005pt and repeated moves accumulate.
At roughly 1/50 of a point, a hundred moves stays under a single point. This is
documented rather than fixed: carrying higher-precision output everywhere to
serve one operation is not worth it.

### What moves and what resizes

| Kind | Move | Resize |
|---|---|---|
| Ink, including signatures | yes | aspect locked |
| Rectangle, oval, line, arrow | yes | free |
| Stamp | yes | aspect locked |
| Sticky note | yes | no — fixed icon size |
| Text markup | no | no |

Ink is aspect-locked because stretched handwriting reads as wrong, and a
signature is ink — the same rule SP-3d set when placing one. Stamps are locked
because a squashed APPROVED reads as broken.

### It lives in Edit-annotations mode

Selection already works there. This adds a drag to move the selection and four
corner handles to resize it, with a live outline. Nothing new to enter or leave.

## Architecture

### `lib/domain/annotations/annotation_transform.dart` — new

```dart
/// Maps a point from [from] into [to].
PdfPoint transformPoint(PdfPoint p, {required TextRect from, required TextRect to});

/// Rewrites /Rect and every coordinate-pair geometry key in [dict] so they
/// agree. Returns the dictionary unchanged when [from] has zero area.
String transformAnnotationDict(String dict, {required TextRect from, required TextRect to});

/// The rect [proposed] would become with aspect ratio locked to [original].
TextRect lockAspect(TextRect proposed, {required TextRect original});
```

`transformAnnotationDict` rewrites `/Rect`, `/InkList`, `/L` and `/QuadPoints`.
It touches no other key, so colour, width and appearance references survive.

### Changes to existing files

- `annotation_edit_session.dart` — `moveTo(int objectNumber, TextRect rect)`,
  `Map<int, TextRect> get moved`, both included in the undo snapshot.
- `pdf_annotation_editor.dart` — `applyAnnotationEdits` gains
  `required Map<int, TextRect> moved`. A moved annotation's override runs
  through `transformAnnotationDict`; it emits **no** new appearance. An
  annotation both moved and restyled gets one override carrying both.
- `annotation_edit_repository.dart` and its impl — `save` gains `moved`.
- `annotation_edit_providers.dart` — `moveSelected(TextRect)`.
- `annotation_selection_overlay.dart` — drag to move, four corner handles,
  live outline, and the per-kind resize rules.
- `annotation_edit_toolbar.dart` — unchanged, but Save now also commits moves.

### Which annotations may be moved

`SavedAnnotation` gains two getters:

```dart
/// Markup is anchored to the words it covers.
bool get movable => subtype != 'Highlight' && subtype != 'Underline' && subtype != 'StrikeOut';

/// A /Text icon is drawn at a fixed size by every viewer.
bool get resizable => movable && subtype != 'Text';
```

## Risks

**`applyAnnotationEdits` gains a third operation.** Every SP-3c and SP-3e test
is the guard that deletes and restyles still behave, and a mutation that
transforms `/Rect` without the geometry must turn the new tests red.

**Handles on small annotations.** A note icon is 20pt; corner handles would
cover it entirely. Notes are move-only, so they get no handles, which sidesteps
this.

## Testing

Unit:

- `transformPoint` maps each corner of the old rect onto the corresponding
  corner of the new one exactly;
- a zero-area source rect returns the dictionary unchanged rather than dividing
  by zero;
- `transformAnnotationDict` rewrites `/Rect` **and** `/InkList` consistently;
- a dictionary with no geometry key has only its `/Rect` changed;
- colour, width and `/AP` survive a move untouched;
- `lockAspect` preserves the original ratio for both a taller and a wider drag;
- `movable` and `resizable` per subtype;
- the session's undo covers a move, and a move plus a restyle;
- every SP-3c and SP-3e test still passes.

Integration, all verified by rendering:

- a moved annotation draws in its new position and **not** its old one;
- **restyling after a move keeps the new position** — the regression test for
  the stale-geometry trap;
- a stamp moves even though it is delete-only for restyling;
- a resized shape covers more of the page than before;
- source documents stay byte-identical.

Mutations: rewrite `/Rect` without transforming geometry; drop the aspect lock.

## Definition of done

- [ ] Drag to move, corner handles to resize, inside Edit annotations
- [ ] Markup cannot be moved; notes cannot be resized
- [ ] Ink and stamps resize with aspect locked; shapes resize freely
- [ ] `/Rect` and geometry always agree after a move, proven by mutation
- [ ] Restyling after a move keeps the new position
- [ ] Every SP-3a through SP-3e test still passes
- [ ] `PdfEngine` still has no write method
- [ ] Integration green on iOS simulator and Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] All four CI jobs green, `build-windows` included
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md`, `TESTING.md` updated
