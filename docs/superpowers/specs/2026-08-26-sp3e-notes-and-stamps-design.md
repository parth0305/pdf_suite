# SP-3e — Sticky notes and stamps

**Status:** approved, ready for planning
**Date:** 2026-08-26
**Depends on:** SP-3a, SP-3b, SP-3c, SP-3d.

## Problem

Folio can mark up text, draw, and sign, but it cannot leave a comment. The two
annotations people reach for on a document they are reviewing — a note saying
why, and a stamp saying what happens next — are both missing.

## Probed before designing

Three questions were answered on device on 2026-08-26 rather than assumed:

| Question | Answer |
|---|---|
| Does PDFium draw a `/Text` note without an `/AP`? | **Yes** — 692 pixels changed |
| Does a non-embedded standard-14 `/Helvetica` render? | **Yes** — 3927 pixels changed |
| Does a `/Stamp` render without an `/AP`? | **No** — 0 pixels changed |

Those results shape the whole slice: notes need no appearance stream, stamps
need one, and neither needs an embedded font.

## Scope

**In:** sticky notes as `/Text` annotations with popup content; six preset
`/Stamp` marks; editing a saved note's text.

**Out, deliberately:**

- **Custom or user-managed stamps.** The preset set covers what stamps are for.
  Custom stamps would need a table, a management sheet and rename/delete — the
  signature-library work again, and it would push notes into a later slice.
- **Date stamps.** A small code addition that raises questions worth answering
  properly: which format, whose timezone, frozen or re-evaluated. A wrong date
  on a stamped document is worse than no date.
- **`/FreeText` notes** — text drawn onto the page rather than an icon. Feasible
  now that the font question is settled, but it obscures page content and needs
  line wrapping.
- **Restyling stamps.** They stay delete-only. Reconstructing one from `/Name`
  is possible; it is not in this slice, and the list says so rather than
  offering a control that does nothing.

## Decisions

### A note has no appearance stream

`/Text` with `/Rect`, `/Contents`, `/Name /Note` and `/C`. PDFium draws the
icon, so generating an appearance would only risk disagreeing with what every
other viewer draws. The text lives in `/Contents`, where it stays searchable
and copyable, and it never covers the page.

This forces one change to the writer: `writeAnnotations` currently emits an
`/AP` object for **every** annotation. Appearance generation becomes optional
per kind.

### A stamp is sized from its label, not measured

Text is centred by construction rather than by metrics:

```
width = 2 × padding + label.length × fontSize × 0.75
```

0.75 em is a safe upper bound for uppercase Helvetica, so the label always
fits. Measuring text properly would mean carrying a width table for a font we
do not embed; guessing badly is how stamps end up with clipped words.

Height is fixed at `fontSize + 2 × padding`.

### Both join the sealed `Annotation` type

`StickyNote` and `Stamp` become members alongside `TextMarkup` and
`DrawingAnnotation`. The writer's switch stops being exhaustive until they are
handled, which is a compile error rather than a silently dropped annotation —
the reason the type was sealed in SP-3b.

### Placement is a tap, not a drag

A note is a fixed 20×20pt icon; a stamp's box is determined by its label. There
is nothing for a drag to size. Dragging would also imply resizing, which is
SP-3f's job.

### Editing note text extends `AnnotationStyle`

`AnnotationStyle` gains an optional `contents`. When it is present and the
target is a note, the override rewrites `/Contents` and emits no `/AP`.
Geometry is still copied verbatim, exactly as SP-3c requires.

## Architecture

### `lib/domain/annotations/sticky_note.dart` — new, part of `annotation.dart`

```dart
final class StickyNote extends Annotation {
  const StickyNote({
    required this.pageIndex,
    required this.anchorPt,      // top-left of the icon, PDF space
    required this.contents,
    this.colorArgb = 0xFFFFC107,
  });

  @override
  final int pageIndex;
  final PdfPoint anchorPt;
  final String contents;
  final int colorArgb;

  @override
  String get pdfSubtype => 'Text';

  /// PDF's conventional note icon size.
  static const double iconSizePt = 20;
}
```

### `lib/domain/annotations/stamp.dart` — new, part of `annotation.dart`

```dart
enum StampPreset { approved, rejected, draft, confidential, reviewed, urgent }

final class Stamp extends Annotation {
  const Stamp({
    required this.preset,
    required this.pageIndex,
    required this.anchorPt,      // top-left, PDF space
  });

  @override
  final int pageIndex;
  final StampPreset preset;
  final PdfPoint anchorPt;

  @override
  String get pdfSubtype => 'Stamp';

  String get label;             // 'APPROVED', …
  int get colorArgb;            // per preset
  double get widthPt;           // sized from the label
  double get heightPt;
}
```

Both are `part` files of `annotation.dart`, because Dart permits a sealed type
to be extended only within its own library — the constraint SP-3b already hit.

### `lib/domain/annotations/stamp_appearance.dart` — new

```dart
String stampAppearanceStream(Stamp stamp);
String stampAppearanceDict(Stamp stamp, int streamLength, int fontObjectNumber);
String helveticaFontObject();
```

The dictionary carries `/Resources << /Font << /F1 N 0 R >> >>`, and the writer
emits one shared `/Type /Font /Subtype /Type1 /BaseFont /Helvetica` object per
save rather than one per stamp.

### Changes to existing files

- `pdf_annotation_writer.dart` — appearance generation becomes optional; a
  shared font object is emitted once when any stamp is present; the geometry
  switch gains `/Contents` for notes.
- `pdf_annotation_reader.dart` — reconstructs a `StickyNote` from `/Contents`
  so its text can be edited. `/Stamp` stays unreconstructed, hence delete-only.
- `pdf_annotation_editor.dart` — `AnnotationStyle.contents`; a note override
  rewrites `/Contents` and emits no `/AP`.
- `annotation_providers.dart` — `addNote` and `addStamp`.
- `viewer_screen.dart` — `_ViewerMode.note` and `_ViewerMode.stamp`.

### UI

- `NoteDialog` — a text field, used both when placing and when editing.
- `StampPicker` — a row of the six presets in their own colours.
- `NotePlacementSurface` and `StampPlacementSurface` — tap-to-place overlays,
  present only in their own modes so they cannot compete with the viewer for
  scroll or pinch.

## Risks

**The writer's optional-appearance change touches shipped code.** Every SP-3a,
SP-3b and SP-3d test is the guard, and a mutation that emits an `/AP` for notes
must turn them red.

**0.75 em is an assumption.** It is an upper bound for uppercase Helvetica, and
the preset labels are known and fixed, so the risk is a slightly wide box
rather than clipped text. The test asserts the box grows with label length.

## Testing

Unit:

- a note's dictionary contains `/Contents` and **no** `/AP`;
- a stamp's dictionary references a font resource, and the font object is
  emitted once for several stamps;
- stamp box width grows with label length;
- the sealed switch covers all four annotation kinds;
- `AnnotationStyle.contents` rewrites `/Contents` and leaves `/Rect` untouched;
- every SP-3a, SP-3b, SP-3c and SP-3d test still passes.

Integration, all verified by rendering:

- a placed note draws its icon;
- a placed stamp draws its label;
- deleting either removes it;
- editing a note's text changes `/Contents` while its `/Rect` stays
  byte-identical;
- notes and stamps save together with markup and drawings in one pass;
- source documents stay byte-identical.

Mutations: emit an `/AP` for notes anyway; give the stamp box a fixed width
regardless of label.

## Definition of done

- [ ] Place, save and delete sticky notes; edit a saved note's text
- [ ] Place, save and delete all six stamp presets
- [ ] Notes carry no appearance stream; stamps carry one and render
- [ ] Stamps are labelled delete-only in Edit annotations
- [ ] Every earlier test still passes
- [ ] `PdfEngine` still has no write method
- [ ] Integration green on iOS simulator and Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] All four CI jobs green, `build-windows` included
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md`, `TESTING.md` updated
