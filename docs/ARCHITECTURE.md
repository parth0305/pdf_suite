# Architecture

## Layering

```
Flutter UI            lib/features/*
      │
Application / Domain  lib/domain/*      pure Dart; no Flutter, no native
      │
Repository interfaces lib/domain/repositories
      │
Data layer            lib/data/*        drift, file system, platform channels
      │
PdfEngine interface   lib/domain/engine
      │
      ├─ PdfrxEngine  lib/engine        PDFium, production
      └─ FakePdfEngine test/fakes        unit tests, no native code
```

## The PdfEngine boundary

`PdfEngine` exposes **no write, save, or export method**. That is not an
oversight — it makes "SP-1 cannot alter a PDF" a property the compiler enforces
rather than a promise in a code review.

It is also a *testing* requirement. PDFium is native code, so anything touching
it needs a simulator or device. CI's Ubuntu and Windows runners have neither.
Routing domain logic through the interface lets unit tests inject
`FakePdfEngine` and run anywhere, which is what makes the 80% business-logic
coverage target reachable.

### Deliberate exception: the viewer uses pdfrx directly

`features/viewer` uses pdfrx's `PdfViewer` widget rather than routing rendering
through `PdfEngine`. `PdfViewer` is a UI component with its own tile cache,
scroll physics and bitmap lifecycle; reimplementing that over `renderPage`
would be worse code and worse performance.

`PdfEngine` remains the only path for **headless** work — text extraction,
outline, permissions — which is what unit tests exercise.

## The write path is a separate interface

`PdfEngine` has no write method, and SP-2a deliberately did not add one. Page
editing goes through `PdfPageEditor`, a separate interface with a single
`materialise` method.

Merging them would have been less code and would have silently dissolved the
guarantee for every existing `PdfEngine` caller. The Definition of Done for
SP-2a includes a check that `PdfEngine` is still write-free.

Editing is **staged**: a `PageEditSession` holds an ordered `List<PageSlot>` and
a command stack, and every operation is a list manipulation in pure Dart. Only
"Apply" materialises. Three consequences follow — undo is a stack of in-memory
snapshots rather than a history of file writes, the operation logic is
unit-testable with no simulator, and an abandoned session cannot leave partial
files behind.

## One write path into the library

Every produced document enters through `DocumentWriter.store`. Metadata
re-attachment lives there, so a new writer cannot forget it — which is exactly
how the SP-2b data-loss bug happened, in a private method only one caller could
reach.

## Annotations are written, not overlaid

Text markup becomes real PDF annotation objects rather than rows in Folio's
database drawn over the page. Database-backed markup would have been far simpler,
and invisible to every other viewer — which defeats what "annotate" means.

The write uses the same incremental-update technique as metadata, with one extra
requirement: the page dictionary must be **overridden** to carry `/Annots`. That
is what `PdfObjectReader` exists for. It matches dictionaries by brace balance
rather than regex, and merges into an existing `/Annots` array rather than
replacing it. It parses page dictionaries and nothing else, deliberately.

`Annotation` is a **sealed** supertype of `TextMarkup` and `DrawingAnnotation`,
so the writer's switch over annotation kinds is exhaustive: adding a kind
without teaching the writer about it is a compile error, not a silently
dropped annotation. Dart only allows a sealed type to be extended inside its
own library, so the three types are one library made of `part` files.

Both kinds share one `AnnotationSession`, and therefore one undo stack and one
Save. Two parallel sessions would have given the user two undo stacks and
produced two documents from a single editing sitting.

## One object index, two narrow readers

`PdfObjectIndex` maps an object number to its latest dictionary. It owns the
two mechanics any object lookup needs: dictionaries matched by brace balance,
and **the last definition of an object number wins**, which is what a reader
walking the trailer chain backwards sees.

That second rule is not a detail. Reading a superseded page dictionary merges
into a stale `/Annots` and orphans every annotation saved before it — a
data-loss bug that shipped in SP-3a and was found only when a spike compared
rendered pixels rather than bytes.

`PdfObjectReader` still handles page dictionaries and nothing else;
`PdfAnnotationReader` resolves `/Annots` references through the same index.
Two bounded readers, rather than one file growing toward a PDF parser.

## Ink carries strokes, not points

`/InkList` is defined as an array of stroke arrays. SP-3b only ever emitted one,
so a drawing was a single polyline — a shape that cannot represent a signature
without drawing lines through the gaps between pen strokes.

Geometry is therefore `strokes: List<List<PdfPoint>>`, with `points` kept as
`strokes.first` so the fourteen non-ink uses are untouched.

This corrected a live defect: the reader flattened `/InkList`, so restyling a
multi-stroke ink annotation from another tool regenerated its appearance with
the strokes joined. `boundsPt` had the same blind spot and would have bounded
only the first stroke, clipping the rest away via the `/BBox`.

## Appearance streams are per-kind, not universal

Probed on device rather than assumed: a `/Text` note renders **without** an
appearance stream (692 pixels changed), and a `/Stamp` renders **nothing**
without one (0 pixels). So appearance generation is optional per annotation
kind, not a step every annotation goes through.

A note therefore carries no `/AP` at all. Generating one could only disagree
with the icon every viewer already draws, and it would put the note's meaning
in two places at once.

## Standard-14 fonts are referenced, never embedded

Stamp labels are drawn with `/BaseFont /Helvetica` and no font file. The
fourteen standard fonts are built into every conforming viewer, so no font data
is shipped and no font licence is involved — verified on device at 3927 pixels
changed.

The stamp box is **sized from its label** rather than measured:
`2 × padding + label.length × fontSize × 0.75`. 0.75 em is a safe upper bound
for uppercase Helvetica, so the text fits by construction. Carrying a width
table for a font we do not embed is not worth the accuracy.

## Signatures are stored normalised, y-up

A saved signature holds its strokes in a unit box with y increasing upward, the
same orientation as PDF user space, so placement is a multiply and an offset
with no flip. The canvas-to-PDF flip happens once, at capture.

Placement fits the signature inside the dragged box rather than filling it.

## Encryption: two handlers, one reachable

Folio implements both PDF standard security handlers it needs:

| Handler | Cipher | Reachable |
|---|---|---|
| Revision 2 | RC4-40 | **No.** It is the reference the pipeline was proven against, and it is not protection worth offering. |
| Revision 6 | AES-256 | Yes — "Protect with password". |

They differ in a way that is easy to get wrong by analogy: revision 2 derives a
**per-object key** from the file key and the object number, while revision 6
uses the file key **directly** for every string and stream. Applying R2's
scheme under V5 produces a document nothing can open — mutation-tested at
7,308 pixels.

A protected document carries no re-attached metadata. `PdfMetadata` appends an
incremental update, and an unencrypted update sitting after an encrypted
document would defeat the encryption.

### Two passwords, and permissions that are only a request

Revision 6 stores two independent key wrappings of the same file key: `/UE`
under the user password and `/OE` under the owner password. Either recovers the
same 32 bytes, which is why either opens the document. The owner entry hashes
the 48-byte `/U` as extra data, binding both passwords to one file. Omit the
owner password and Folio wraps the key under the user password twice, because
a restriction nobody can lift restricts the author too.

Permissions live in `/P`, written in the clear so a reader can act on them
before it has a key, and again inside `/Perms`, encrypted with the file key so
a reader can tell whether `/P` was edited. The two must agree: PDFium treats a
mismatch as tampering and rejects **every** password, which is exactly what a
mutation of this code demonstrated.

`PdfPermissions` is the only place that knows bit numbering, and it clears
dependent bits together — denying printing also denies high-quality printing,
denying modification also denies assembly, denying annotation also denies form
filling. Nothing downstream reasons about individual bits.

## Two write models, and when each applies

Folio writes documents two ways.

**Incremental update** — append new objects, an overridden page dictionary, a
new cross-reference section and a trailer chaining to the previous one. The
original bytes are never touched. Everything through SP-4a works this way:
metadata, annotations, watermarks.

**Full rewrite** — parse every object, emit them all, write a fresh
cross-reference table and a trailer with no `/Prev`. Verified by rendering: a
rewritten document differs from its original by **zero pixels**.

Encryption is what forces the second. Encrypting a document means encrypting
every string and every stream in it, so every object must be re-emitted; there
is nothing to append. Compressing an existing document and redacting one need
the same thing.

Two rules the rewrite depends on:

- **`/Length` decides where an object ends**, not the word `endobj`. Binary
  stream data can contain those bytes, and searching for them ends the object
  inside its own stream.
- **`/Encrypt` and the document `/ID` are never encrypted.** A reader needs
  both in the clear before it can derive any key.

Each object is encrypted with its **own** key, derived from the file key and
the object number. Reusing the file key produces a document that opens in some
readers and not others — mutation-tested at 7,308 pixels.

## Writing page content, and what it costs

SP-4a is the first slice that writes page **content** rather than annotations.
It appends a content stream to each page's `/Contents` and overrides the page
dictionary — proved on device at 3,075 pixels changed with the original bytes
byte-identical.

Three rules make it safe:

- **The stream is `q`/`Q` balanced.** It runs after the page's own content, and
  an unbalanced stream leaks graphics state into everything appended after it.
- **`/Resources` is merged, never replaced.** Replacing strips the fonts the
  page's own content depends on and the page renders blank. Asserting both
  entries are merely *present* is not enough — a writer that appends a second
  `/Resources` passes that check while a reader takes only one of them, so the
  test asserts there is exactly one.
- **`/MediaBox` is resolved through inheritance**, in a sibling file rather
  than in `PdfObjectReader`: following `/Parent` means reading a node that is
  not a page dictionary, which that reader's own documentation forbids.

## Why compression and encryption needed the object layer

Both were probed alongside watermarks and neither could be done by appending:
an incremental update only ever *grows* a file, so compressing by appending is
self-defeating, and encrypting a document means every string and stream in it
must be encrypted. Both needed a full-file rewrite, which SP-5a built and
SP-5b/5c used.

`dart:io`'s `ZLibCodec` is available with no dependency and PDFium accepts a
stream we compressed, so Flate itself was never the obstacle — the write model
was.

### Compression is size-aware, and the filter declaration counts

Every stream Folio writes goes through `pdfStreamBody`, which deflates **only
when that makes the file smaller**. The comparison includes the 21 bytes of
` /Filter /FlateDecode` that must go into the dictionary, because leaving them
out is not a rounding error: a 119-byte watermark stream deflates to 107, and
compressing all three pages of a document grew it by 27 bytes. Short appearance
and watermark streams are therefore stored raw, and long ones are deflated.

A consequence worth remembering when writing tests: a five-letter watermark is
**not** compressed, so a test that expects `/FlateDecode` must use a mark long
enough to earn it.

## Two ways to put an image in a PDF, and when each applies

Folio writes images two ways, and the choice is about where the pixels came
from.

**Raw RGB under `/FlateDecode`** (SP-5d, redaction). The pixels are a rendering
Folio produced at a resolution Folio chose. There is no compressed original to
preserve, and deflate is already in `dart:io`.

**The JPEG untouched under `/DCTDecode`** (SP-6a, scanner). The pixels arrived
as a photograph that is already compressed. Decoding it to re-encode it would be
worse in every direction: a twelve-megapixel photo is 36 MB as raw RGB,
photographs barely deflate, and it would need an image codec Folio does not
have. `/DCTDecode` has been in PDF since 1.2 precisely for this.

Both shapes were proven by a throwaway device probe before anything was built on
them, because Folio had never written an image XObject of either kind.

### EXIF is not optional detail

PDF ignores EXIF orientation completely. A camera JPEG embedded as-is appears
rotated whenever the phone recorded orientation in metadata rather than in the
pixels, which is most portrait shots. `image_picker` is asked for `maxWidth` and
`imageQuality` so the platform resizes and re-encodes, and **that step bakes
orientation into the pixels**. The size reduction is welcome; the orientation is
the reason.

## Compression: measured first, and lossless by necessity

Compression was designed backwards from a measurement. Task 1 analysed sixteen
real documents before any of it was written, and the result inverted the plan:
**deflating uncompressed streams gains almost nothing** on real PDFs, because
they arrive already compressed. Only Folio's own simple output benefits.

**Deduplication is the win.** A merged set of five bank statements was 37%
byte-identical objects — merging duplicates every shared font and image, and
Folio has a merge feature, so it produces exactly that shape.

Three exact transformations run through the object layer's full rewrite:
identical objects collapse to one, unreferenced objects are dropped, and
uncompressed streams are deflated.

### The saving is measured, never predicted

`compressPdf` returns the compressed bytes *and* the result, and the saving is
the real difference in file size. A per-object estimate was tried and
over-promised by 215 bytes: it cannot model the rewrite's own overhead — a
fresh cross-reference table, a document `/ID`, free entries where objects were
dropped. A number shown to a user before they commit must never exceed what
they get.

Keeping the bytes also means accepting the offer cannot produce a different
file from the one that was measured.

### Two rules that keep it safe

**Only byte-identical objects collapse.** Two objects differing by whitespace
mean the same thing to a reader, but proving that needs a parser, and
collapsing merely-equivalent objects is how a compressor corrupts a document.

**References are remapped in dictionaries only, never in stream payloads.** A
compressed image's bytes are arbitrary; bytes that happen to read as `6 0 R`
are image data. Rewriting them corrupts the image while leaving the file
structurally valid — the worst kind of failure, because everything still opens.

## OCR adds a layer; it never touches the page

An OCR pass appends an **incremental update**. Nothing is being removed, so the
original bytes staying at the front of the file is exactly right — the opposite
of redaction, and the reason those two features write so differently despite
both producing a text layer.

The page dictionary's `/Contents` is **appended to**, never replaced: the scan
still has to be drawn. `/Resources` are **merged**, never substituted —
replacing them would strip the page's own font and image, which for a scanned
page means losing the scan. A device test asserts OCR changes zero pixels,
which is the only thing that would catch either mistake.

### Two paths, because one platform cannot supply positions

Tesseract can report each word's bounding box through hOCR. Folio uses that on
Android and places every word where it appears, so a search highlight lands on
the word.

On iOS the plugin's `extractHocr` **blocks the platform thread indefinitely** —
a 90-second Dart timeout never fired, so this is measured rather than inferred.
That platform gets plain text, and `ocrTextLayer` falls back to placing whole
lines by reading order.

The fallback is a real compromise and is labelled as one everywhere it appears:
in the UI, in `FEATURES.md`, and in `LIMITATIONS.md` §5. What it preserves is
reading order and searchability; what it loses is precise position.

Only one test observes the difference — the others pass on either path, because
both produce extractable text. It compares the gap between two adjacent lines
against a quarter of the page, and separately checks the title is in the top
half: the gap alone is mirror-symmetric, so a missing y-flip passes it
upside-down.

## Redaction: why it rewrites, and why the text layer is rebuilt

Redaction is the one feature where an incremental update is not merely
suboptimal but **wrong**. An incremental update appends: the original bytes stay
at the front of the file. Redacting that way would leave the content stream
carrying the redacted text fully intact, ahead of the update that hides it, and
any text editor would find it. Redaction goes through `writePdfDocument` and
omits the old content stream objects from the list entirely.

It also omits XObjects that only the redacted pages referenced. An image under a
black box lives in an XObject, not in the content stream — dropping the content
stream alone leaves it recoverable. An XObject a surviving page still uses is
**kept**: it is visible in the output anyway, so removing it would break that
page and conceal nothing.

### The text layer is rebuilt, not edited

The alternative design was operator surgery: parse the content stream and cut
out the text-showing operators. It was rejected. It needs a content-stream
parser Folio does not have, its correctness turns on font encodings, `TJ`
kerning arrays and text-matrix accumulation, and it does nothing about an image
under the box. Worst of all, its failure mode looks exactly like success.

Instead the page is thrown away and rebuilt: rasterised at 200 DPI with the
boxes painted in, then the surviving characters are re-emitted as invisible text
(`3 Tr`) from the rectangles PDFium already reports. Folio never subtracts the
redacted text from anything, which is what makes the removal unconditional.

### Two things the device told us that no unit test could

**One `Tj` per character destroys search.** PDFium inserts a word-break space
wherever it sees a gap between glyphs, so a page whose every character is its
own text object extracts as `C o n f id e n t ia l`. Characters are emitted in
**runs**; within a single `Tj` the reader spaces glyphs by the font's own
advances.

**Runs must not be split on glyph geometry.** The first attempt broke a run when
rect bottoms differed, on the theory that this detected a line change. A
descender sits lower than its neighbours and a hyphen sits higher, so `rupees`
became `ru p ees` and `REDACT-ME-9931` became `REDACT - ME - 9931`. PDFium
already reports newlines between lines, so the text's own whitespace is the only
separator needed — and a removed character, which must also end a run or the
halves either side of a redaction would join into a word that never existed.

## Moving is a rect rewrite, and the appearance follows

Probed on device: changing only `/Rect` moved a mark from columns 20..59 to
200..239, and enlarging `/Rect` scaled it from 40 to 120 columns. PDFium
implements the ISO 32000-1 §12.5.5 mapping of an appearance `/BBox` onto its
`/Rect`, so **no appearance is regenerated when an annotation moves**.

The geometry keys are rewritten by the same affine anyway, so `/Rect` and
`/InkList`, `/L` and `/QuadPoints` never disagree. That is *not* because a
stale geometry would render wrongly — it would not, since the BBox mapping
rescues it — but because the file would be internally inconsistent for viewers
that do not honour `/AP` and for any code that reads geometry positionally.

The consequence for testing is sharp: **this class of bug is invisible to
rendering**. It can only be caught by reading the geometry back.

Because the transform works on the raw dictionary, it needs no reconstruction —
which is why a stamp can be moved even though Folio cannot rebuild one well
enough to restyle it.

## An edit may never move what it did not compute

Restyling copies every geometry key out of the source dictionary as a raw
substring. Only `/C`, `/BS` and `/AP` are rewritten. Moving is the one
operation that *is* a request to change geometry, and is the stated exception.

`pdfNumber` formats to two decimals, so re-emitting geometry from parsed
doubles would shift an annotation by up to 0.005pt — invisible in review,
invisible in every byte assertion, and permanent. A mutation test enforces it.

The appearance stream is regenerated from parsed values, which is fine: an
appearance is derived, and the error is orders of magnitude below visibility.

## In-place editing repoints a row; it does not overwrite a file

Managed files are content-addressed, so editing a document's bytes changes
where it lives. Rewriting in place means writing the new file, repointing the
library row, and deleting the old file **only when no other row references
it** — identical documents are stored once, so deleting on one document's
behalf would break every other document sharing it.

## Screen coordinates are converted at one tested boundary

A drawing is captured in canvas pixels and must be written in PDF user space,
which is y-**up** and measured in points. Getting that flip wrong puts every
stroke at the mirror image of where the user drew it.

The conversion is two pure functions, `canvasToPdf` and `pdfToCanvas` in
`page_coordinates.dart`, tested directly rather than only through the UI: they
normalise against the page's on-screen rect, so zoom and scroll need no special
handling — a stroke lands under the finger at any zoom because the rect grows
with it.

The drawing preview converts staged points *back* with `pdfToCanvas` rather
than keeping a second copy in canvas space, so what the user sees on screen and
what gets written cannot drift apart.

## Metadata is preserved by incremental update

The writer discards a source document's `/Info`, so page operations would
otherwise silently destroy every document's title and author.

Rather than parse and rewrite the document, `PdfMetadata` appends a **PDF
incremental update**: the original bytes untouched, then a new `/Info` object, a
new xref section listing only it, and a trailer whose `/Prev` chains to the
previous one. Readers walk that chain backwards, so the new `/Info` supersedes
any older one. Roughly 200 bytes of overhead and no object model required.

This assumes a classic xref table, which is what our own writer emits. It would
need extending for PDF 1.5+ cross-reference streams, and is therefore only
applied to documents Folio itself produced.

Re-attachment happens in one place - `PageOperationsRepositoryImpl._store` -
so every operation inherits it, and it is best-effort: a document that cannot be
patched is still written, because losing a title is better than losing the file.

## Document identity

The single most important decision in the data layer.

A file path is a durable handle on Windows and a lie on mobile:

- **iOS/iPadOS** — a picked URL grants temporary access. Reopening after
  relaunch requires a **security-scoped bookmark** captured at pick time.
- **Android** — the Storage Access Framework returns a `content://` URI scoped
  to one grant. Durable reuse requires `takePersistableUriPermission`, and a
  filesystem path cannot be granted one at all.

So `DocumentRef` stores a platform-appropriate handle, never a bare string:

| Variant | Handle | Durable on |
|---|---|---|
| `ManagedRef` | app-owned content-addressed path | everywhere |
| `ExternalRef` + `BookmarkHandle` | security-scoped bookmark | iOS, macOS |
| `ExternalRef` + `ContentUriHandle` | persisted SAF URI | Android |
| `ExternalRef` + `PathHandle` | absolute path | Windows |

### Import copies in

Opening a document copies it into an app-owned library directory under
Application Support. Consequences:

- Recents and Favorites always reopen, on every platform.
- The app owns the file, so atomic-write discipline applies cleanly.
- Costs storage, and the copy is content-addressed so identical bytes
  deduplicate.

"Open in place" remains available and produces an `ExternalRef`, which is
allowed to go stale; unresolvable entries surface as typed failures rather than
crashes.

## Virtual folders

Managed files are stored content-addressed and flat, so collections are a
nullable `collectionId` column rather than real directories. A move is an
`UPDATE`, not a file operation that could fail halfway, and
`onDelete: setNull` guarantees deleting a collection returns its documents to
the root instead of cascading into deleting them.

## Data safety

`SafeFileWriter` implements the required pipeline:

```
input → temp working file (same directory) → validate → flush → atomic rename
```

The temp file is placed in the destination directory so `rename` is atomic
rather than degrading to a cross-volume copy. A failed or rejected write never
leaves a partial file and never clobbers an existing destination.

## Responsive layout

Layout branches on **width class**, never on `Platform.isX`, so a narrow desktop
window behaves like a phone:

| Width | Layout |
|---|---|
| `< 600dp` | bottom navigation, single pane, panels as bottom sheets |
| `600–1024dp` | navigation rail, docked side panels |
| `> 1024dp` | extended rail, docked side panels |

Platform checks are permitted only for genuine capability differences — file
pickers and permissions.
