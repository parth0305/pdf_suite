# SP-3c — Editing and deleting saved annotations

**Status:** approved, ready for planning
**Date:** 2026-08-26
**Depends on:** SP-3a (text markup), SP-3b (ink and shapes), and the
incremental-update override fix merged in PR #6.

## Problem

Annotations can be created but never changed. Once saved, a highlight in the
wrong colour or a stray ink stroke is permanent — the only recourse is to
discard the document and annotate the original again.

`FEATURES.md` and `LIMITATIONS.md` have carried "editing or deleting saved
annotations is not possible" since SP-3a. This slice removes that entry.

## Scope

**In:**

- Delete any annotation in the document, whatever tool wrote it.
- Restyle — colour and stroke width — for annotations whose geometry we can
  read back.
- A dedicated Annotations mode for selecting them.

**Out, deliberately:**

- Moving, resizing or reshaping. `/QuadPoints` are anchored to text, so moving
  markup is meaningless; moving a drawing is real but roughly doubles the UI
  work and is not what people reach for. They delete and redraw.
- Compacting orphaned objects. Repeated edits leave superseded `/AP` streams in
  the file. That is a size cost, not a correctness one.
- Creating annotations. That is SP-3a and SP-3b, already shipped.

## Decisions

### Delete is universal; restyle is conditional

Deleting needs no understanding of an annotation — it is one reference removed
from `/Annots`. It therefore works on anything.

Restyling means regenerating an appearance stream, which needs the annotation's
geometry. An annotation is restylable when we can read the geometry key its
subtype implies:

| Subtype | Geometry key |
|---|---|
| `/Highlight`, `/Underline`, `/StrikeOut` | `/QuadPoints` |
| `/Ink` | `/InkList` |
| `/Square`, `/Circle` | `/Rect` |
| `/Line` | `/L` |

Anything else is delete-only, and the list row says so. A control that is
silently absent reads as a bug; a control that is absent with a stated reason
reads as a boundary.

This rule deliberately does **not** ask whether Folio wrote the annotation.
Folio stamps no marker into the annotations it writes — a consequence of the
standing decision that an edited document should not advertise which tool
touched it — so "our own annotations" is not a distinction the file can make.
Reading the standard geometry keys is a better test anyway: it asks whether we
can do the job correctly, not who did it first.

### Restyle copies geometry verbatim

An override carries new `/C` and `/BS /W` and a fresh `/AP`. Every geometry key
is copied byte-for-byte out of the original dictionary.

We never re-derive coordinates we did not compute. A restyle that could move an
annotation by a rounding error is a restyle that silently corrupts documents,
and the failure would be invisible until someone compared the two renders. This
invariant is enforced by a mutation test, not by care.

### Folio-created documents are edited in place

A new `createdByFolio` column on the library row records provenance. Editing a
Folio-created document rewrites it atomically through `SafeFileWriter`; editing
an imported document produces a new document, exactly as today.

Imported originals are never modified, which is what "never destroy originals"
protects. Without this, fixing one wrong colour three times leaves four
near-identical documents in the library.

### Selection lives in its own mode

`_ViewerMode.annotations` joins Markup and Draw in the Annotate menu. The
selection overlay exists **only** inside that mode, so it cannot compete with
the viewer for scroll, pinch or text selection — the same rule that keeps the
SP-3b drawing surface out of read mode.

Tap hit-tests against `/Rect` converted to canvas space by SP-3b's
`pdfToCanvas`. Overlapping annotations resolve **smallest area first**, so a
large rectangle cannot swallow the highlight drawn on top of it. A side list
panel, following the existing thumbnails and outline panels, covers annotations
too small or too stacked to hit by tapping.

## Architecture

### `PdfObjectIndex` — new

Maps an object number to its latest raw body.

```dart
class PdfObjectIndex {
  static PdfObjectIndex parse(String pdfText);
  String? bodyOf(int objectNumber);
  Iterable<int> get objectNumbers;   // first-appearance order
  bool get usesXrefStream;
}
```

It owns the two mechanics that are genuinely general and are currently trapped
inside `PdfObjectReader`:

- brace-balanced dictionary matching, so nested `<< >>` cannot end a dictionary
  early;
- **last definition of an object number wins**, which is what a reader walking
  the trailer chain backwards sees. Reading a superseded dictionary is what
  caused the orphaning bug fixed in PR #6.

It indexes `N 0 obj … endobj` spans and stops. No typed values, no indirect
resolution, no streams.

### `PdfObjectReader` — refactored, API unchanged

Keeps its page-dictionaries-only mandate and its current public surface, now
reading through the index. Its own documentation states that a caller needing
more than page dictionaries should trigger a scope rethink rather than growth.
This slice is that rethink, and the answer is a sibling, not a bigger file.

### `PdfAnnotationReader` — new

```dart
class SavedAnnotation {
  final int objectNumber;
  final int pageIndex;
  final String subtype;        // without the leading slash
  final TextRect rectPt;      // PDF user space; the name is historical
  final int? colorArgb;        // null when /C is absent
  final double? strokeWidth;   // null when /BS /W is absent
  final bool restylable;
  final String rawDictionary;  // the source of verbatim geometry
}

class PdfAnnotationReader {
  static PdfAnnotationReader parse(String pdfText);
  List<SavedAnnotation> onPage(int pageIndex);
}
```

Resolves each `/Annots` reference through the index and reads five fields.
`/C` is a PDF colour array of components in 0..1; it converts to ARGB with full
opacity. `TextRect` is the existing PDF-space rectangle from `pdf_types.dart` —
`TextMarkup.boundingRect` already returns one, so annotations of every kind
share a single rectangle type rather than gaining a near-duplicate. An annotation whose reference resolves to nothing is skipped rather
than throwing — a dangling reference is a damaged document, not a reason to
refuse the whole page.

### `pdf_annotation_editor.dart` — new

```dart
/// The only things a restyle may change.
class AnnotationStyle {
  const AnnotationStyle({required this.colorArgb, required this.strokeWidth});
  final int colorArgb;
  final double strokeWidth;
}

Uint8List applyAnnotationEdits(
  Uint8List pdf, {
  required List<int> deletedObjectNumbers,
  required Map<int, AnnotationStyle> restyled,
});
```

Emits one incremental update containing:

- an override of each restyled annotation's **same object number**, with new
  `/C`, new `/BS /W`, a reference to a newly emitted `/AP`, and every geometry
  key copied verbatim;
- an override of each affected page dictionary with deleted references removed;
- one xref subsection per object, and a trailer chaining `/Prev` to the previous
  `startxref`.

Documents using cross-reference streams are refused with
`UnsupportedPdfStructure`, consistent with the existing writer.

### `AnnotationEditSession`

Mirrors `AnnotationSession`: pending deletes, pending restyles, undo as
whole-snapshot, `isDirty`. Nothing touches the file until Save.

### UI

- `AnnotationListPanel` — one row per annotation on the page: subtype, colour
  swatch, and "delete only" where restyling is unavailable.
- `AnnotationSelectionOverlay` — hit-testing and the selection outline.
- `AnnotationEditToolbar` — colour row, thickness slider, Delete, and a pinned
  Save. Save is never placed inside a horizontally scrolling row; that was a
  real defect in SP-2a.

## Risks

**pdfrx caches documents by path.** After an in-place write the viewer will
render stale pixels unless the document is explicitly reopened. This is the
highest-risk part of the slice and gets a dedicated integration test that
asserts the *rendered page* changed, not merely that the file changed.

**The library needs a schema migration** for `createdByFolio`. Existing rows
default to false, so previously created documents behave as imported ones and
produce a new document on save. That is the safe direction.

**Orphaned objects accumulate.** Each restyle supersedes an `/AP` stream and
each delete strands an annotation object. Documented in `LIMITATIONS.md`.

## Testing

Unit:

- index: nesting, last-definition-wins, xref-stream detection;
- reader: every subtype in the table, `/C` to ARGB, the restylable rule,
  dangling references;
- editor: delete removes exactly one reference; restyle overrides the same
  object number; **geometry keys are byte-identical to the source**;
- session: undo across mixed deletes and restyles.

Integration, all verified by rendering:

- deleting one annotation stops it drawing while its neighbours still draw;
- restyling changes rendered pixels;
- an in-place save is visible in the viewer without reopening the document by
  hand;
- editing an imported document produces a new document and leaves the source
  hash unchanged;
- a document with annotations Folio did not write can still have them deleted.

## Definition of done

- [ ] Delete works on any annotation, restyle on those with readable geometry
- [ ] Restyle never alters geometry, proven by mutation
- [ ] Folio-created documents edit in place; imported ones produce a new document
- [ ] In-place edits are visible immediately in the viewer
- [ ] `PdfObjectReader` still handles only page dictionaries
- [ ] `PdfEngine` still has no write method
- [ ] Integration green on iOS simulator and Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] All four CI jobs green, `build-windows` included
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md`, `TESTING.md` updated
