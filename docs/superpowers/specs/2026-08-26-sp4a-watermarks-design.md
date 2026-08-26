# SP-4a — Text watermarks

**Status:** approved, ready for planning
**Date:** 2026-08-26
**Depends on:** SP-2a (page operations), SP-3e (standard-14 font handling).

## Problem

Folio can annotate a document but cannot mark one. A watermark — DRAFT,
CONFIDENTIAL, a name, a case number — says something about the document as a
whole, and unlike a stamp it should be part of the page rather than an
annotation anyone can delete in a viewer.

This is also the first slice that writes **page content** rather than
annotations.

## Why this slice, and not compression or encryption

The remaining object-layer work was scoped together and probed on 2026-08-26.
The results split it cleanly:

| Probe | Result |
|---|---|
| Is Flate available with no dependency, and does PDFium accept a stream we compressed? | **Yes** — `dart:io` `ZLibCodec`; 48,000 pixels changed |
| Can a content stream be appended to `/Contents` by incremental update? | **Yes** — 3,075 pixels changed, original bytes byte-identical |

So watermarking needs **no object layer and no new dependency**.

Compression and encryption both do. An incremental update only ever *grows* a
file, so "compress by appending" is self-defeating; and encrypting a document
means every string and stream in it must be encrypted, which cannot be done by
appending either. Both need a full-file rewrite, which is a separate decision
that deserves its own evidence.

## Scope

**In:** a text watermark applied to every page, with size, colour, opacity and
rotation. Saved as a new document.

**Out, deliberately:**

- **Image watermarks.** Needs image XObject embedding, which Folio has never
  done. It would pull the deferred photographed-signature work in sideways.
- **Page ranges.** A watermark marks a document; DRAFT on page 1 only says
  nothing useful. Every document that genuinely wants ranges also wants two
  different watermarks, which a range picker does not give.
- **Tiling.** A repeating watermark multiplies layout questions — spacing,
  stagger, edge clipping — for a mode most documents will not want.
- **Removing a watermark.** It is page content, not an annotation. Removing it
  means rewriting content, which is object-layer work.

## Decisions

### A watermark is page content, not an annotation

If it were an annotation it would be a stamp, which SP-3e already ships — and
which any viewer can delete. Being part of the page is the whole point.

The original document is still never modified: this writes a new document
through the existing `DocumentWriter`, as every slice does.

### The appended stream is wrapped in `q` … `Q`

Our stream runs after the page's own content, so it draws on top. It must
restore the graphics state it found: an unbalanced stream corrupts the
rendering of everything appended after it, including a second watermark.

### `/Contents` has three forms and all three must work

| Form | Handling |
|---|---|
| `/Contents 4 0 R` | becomes `/Contents [4 0 R N 0 R]` |
| `/Contents [4 0 R 5 0 R]` | becomes `/Contents [4 0 R 5 0 R N 0 R]` |
| absent | becomes `/Contents [N 0 R]` |

The project's own fixture uses the first. The other two are common in the wild,
and a watermark that silently does nothing on them would be worse than one that
refuses.

### `/Resources` is merged, never replaced

The watermark needs `/Font << /F1 … >>` for its text and an `/ExtGState` for
its opacity. Both are merged into the page's existing `/Resources`, the same
way `/Annots` already is. Replacing a page's resources strips the fonts its own
content depends on — the page would render blank.

### `/MediaBox` is inheritable

A page dictionary may not carry one, in which case it inherits from its
`/Pages` node. Reading only the page's own dictionary centres the watermark
off-page on exactly the documents that rely on inheritance, so the lookup falls
back to the parent.

### Text is sized from its own length

The same rule as stamps: `width ≈ length × fontSize × 0.6` for mixed-case
Helvetica, used only to centre the text. No font metrics table for a font we do
not embed.

## Architecture

### `lib/domain/watermark/watermark.dart` — new

```dart
enum WatermarkRotation { diagonal, horizontal }

class Watermark {
  const Watermark({
    required this.text,
    this.fontSizePt = 48,
    this.colorArgb = 0xFF9E9E9E,
    this.opacity = 0.3,
    this.rotation = WatermarkRotation.diagonal,
  });

  final String text;
  final double fontSizePt;
  final int colorArgb;
  final double opacity;      // 0..1
  final WatermarkRotation rotation;
}
```

### `lib/domain/watermark/watermark_content.dart` — new

```dart
/// The content stream drawing [mark] centred on a page of the given size.
String watermarkContentStream(Watermark mark, {required TextRect mediaBox});

/// The ExtGState dictionary carrying the watermark's opacity.
String watermarkExtGState(Watermark mark);
```

### `lib/domain/watermark/pdf_watermark_writer.dart` — new

```dart
Uint8List writeWatermark(Uint8List pdf, Watermark mark);
```

One incremental update carrying, per page: the watermark's content stream
object, and an overridden page dictionary whose `/Contents` includes it and
whose `/Resources` carries the font and the ExtGState. The font object and the
ExtGState object are emitted **once** and shared by every page.

Refuses a cross-reference-stream document with `UnsupportedPdfStructure`,
consistent with every other writer.

### `lib/domain/annotations/pdf_object_reader.dart` — modify

Gains `String? mediaBoxOf(PdfPageObject page)` resolving `/MediaBox` with
inheritance, and `String withContentsAndResources(PdfPageObject page, {required int contentObjectNumber, required int fontObjectNumber, required int extGStateObjectNumber})`.

This stays within its page-dictionary mandate: it reads and re-emits page
dictionaries, which is exactly what it already does for `/Annots`.

### `lib/domain/repositories/watermark_repository.dart` and impl — new

`Future<LibraryDocument> apply(int documentId, Watermark mark)`, going through
`DocumentWriter` so metadata is re-attached, as every other write path does.

### UI

A **Watermark** entry in the viewer's overflow menu opens a sheet with a text
field, a font-size slider, the five shared colours, an opacity slider and a
diagonal/horizontal toggle, plus a live preview painted with `CustomPaint`.
Applying saves a new document.

## Risks

**A malformed appended stream corrupts the page.** The `q`/`Q` wrapper is what
prevents it, and a mutation that removes it must turn the tests red.

**Resource merging is where a page gets destroyed.** Replacing `/Resources`
renders the page blank. This is asserted directly, not just implied by a
render test.

## Testing

Unit:

- the content stream is `q`-balanced and contains the text;
- opacity appears as an `/ExtGState` reference, not as a fill alpha;
- the rotation matrix is about the page centre, and horizontal emits none;
- `/Contents` in all three forms;
- `/Resources` merging preserves an existing `/Font` entry;
- `/MediaBox` inherited from `/Pages` is found;
- a cross-reference-stream document is refused.

Integration, all verified by rendering:

- the watermark draws on **every** page, not only the first;
- the document still opens with the same page count;
- the source document is byte-identical afterwards;
- metadata survives.

Mutations: remove the `q`/`Q` wrapper; replace `/Resources` instead of merging.

## Known limitation

A text watermark drawn with `Tj` becomes part of the page's text layer, so
search and extraction find it on every page. That is how most PDF tools behave;
avoiding it means drawing glyph outlines as paths, which is a great deal of
machinery for a modest gain. Documented in `LIMITATIONS.md`.

## Definition of done

- [ ] Apply a text watermark to every page with size, colour, opacity, rotation
- [ ] `/Contents` handled as a ref, an array, and absent
- [ ] `/Resources` merged, proven by mutation
- [ ] Inherited `/MediaBox` resolved
- [ ] Source documents byte-identical; metadata survives
- [ ] `PdfEngine` still has no write method
- [ ] Integration green on iOS simulator and Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] All four CI jobs green, `build-windows` included
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md`, `TESTING.md` updated
