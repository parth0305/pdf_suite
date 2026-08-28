# Features

Status is honest: "verified" means an automated test or a human exercised it on
that platform. A build passing is not verification.

## Legend

- ✅ implemented and verified on that platform
- 🟡 implemented, built, but not exercised on that platform
- ❌ not implemented
- — not applicable

## SP-1 — Foundation and Viewer

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Open / import PDF | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Library list | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Recents | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Favorites | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Search library | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Sort (name/date/size) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Rename / duplicate / delete | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Collections (virtual folders) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Move between folders | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Save As / export | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Page rendering | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Zoom (pinch, buttons, double-tap) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Page navigation + indicator | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Thumbnails panel | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Outline / bookmarks panel | ✅ | ✅ | ✅ | 🟡 | ✅ |
| In-document search + highlight | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Text selection + copy | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Copy restriction honoured | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Password-protected open | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Full screen | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Light / dark theme | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Responsive layout | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Files-app integration | ✅ | ✅ | — | — | ✅ |

**Windows is 🟡 throughout.** It compiles and passes unit tests on CI; no human
or integration test has exercised it. See `LIMITATIONS.md`.

## SP-2a — Page Operations

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Pages mode (thumbnail grid) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Reorder pages (drag) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Delete pages | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Duplicate pages | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Rotate pages | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Extract pages to a new document | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Insert pages from another document | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Merge documents | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Split document (every page or ranges) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Undo / redo page edits | ✅ | ✅ | ✅ | 🟡 | ✅ |

Every operation writes a **new** document and leaves its source
byte-identical, asserted by hash in the integration suite.

## SP-3a — Text markup annotations

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Highlight selected text | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Underline selected text | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Strikethrough selected text | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Undo staged markup | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Save markup into the PDF | ✅ | ✅ | ✅ | 🟡 | ✅ |

Markup is written as real PDF annotation objects, so any viewer can see it.
Verified by rendering the page before and after and requiring the pixels to
differ — a file that merely opens proves nothing.

Editing or deleting markup after it has been saved is **not** yet possible; that
needs reading `/Annots` back, which is not yet scoped.

## SP-3b — Ink and shapes

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Freehand pen | ✅ | ✅ | 🟡 | 🟡 | ✅ |
| Rectangle | ✅ | ✅ | 🟡 | 🟡 | ✅ |
| Oval | ✅ | ✅ | 🟡 | 🟡 | ✅ |
| Line | ✅ | ✅ | 🟡 | 🟡 | ✅ |
| Arrow | ✅ | ✅ | 🟡 | 🟡 | ✅ |
| Colour and thickness | ✅ | ✅ | 🟡 | 🟡 | ✅ |
| Undo staged drawings | ✅ | ✅ | 🟡 | 🟡 | ✅ |
| Save drawings into the PDF | ✅ | ✅ | 🟡 | 🟡 | ✅ |

Drawing needs **no text layer**, so it works on scanned pages where markup
cannot apply — asserted against `scanned_no_text.pdf` by rendering the page
before and after and requiring the pixels to differ.

Drawings and text markup share one session, one undo stack and one Save, so
marking up and drawing in a single sitting produces one document, not two.

Each drawing carries its own appearance stream. That stream is load-bearing,
not decoration: removing it changes exactly zero pixels on reopen, because
PDFium does not synthesise an appearance from `/InkList` or `/L`.

## SP-3c — Editing saved annotations

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Delete a saved annotation | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Change colour | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Change thickness | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Undo staged changes | ✅ | ✅ | ✅ | 🟡 | ✅ |

Deleting works on annotations from **any** producer — it removes a reference,
which needs no understanding of the annotation. Changing colour or thickness
needs to regenerate an appearance, so it is offered only where Folio can read
the geometry back: `/QuadPoints` for markup, `/InkList` for ink, `/Rect` for
squares and circles, `/L` for lines. Anything else is listed as **delete only**
rather than silently ignoring the controls.

Editing a document Folio created updates it in place, so fixing one colour
three times leaves one document rather than four. Editing an imported document
produces a new one and leaves the imported copy byte-identical.

## SP-3d — Signatures

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Draw and save a signature | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Several signatures, labelled | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Place by dragging a box | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Rename and delete signatures | ✅ | ✅ | ✅ | 🟡 | ✅ |

Draw a signature once and reuse it. Placement fits it inside the box you drag,
preserving its aspect ratio — a stretched signature looks forged.

A placed signature is a normal `/Ink` annotation, so it can be deleted or
restyled like anything else, and it renders in any viewer that reads
annotations. It is vector, so it stays sharp at any zoom.

## SP-3e — Sticky notes and stamps

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Place a sticky note | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Edit a saved note's text | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Six preset stamps | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Delete notes and stamps | ✅ | ✅ | ✅ | 🟡 | ✅ |

A note is a PDF `/Text` annotation: viewers draw the icon and show the text in
a popup. It carries **no appearance stream** — PDFium draws the icon itself —
so the text stays searchable and copyable and never covers the page.

Stamps are Approved, Rejected, Draft, Confidential, Reviewed and Urgent, drawn
with a non-embedded standard-14 Helvetica. No font data is shipped.

## SP-3f — Moving and resizing

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Drag a saved annotation to move it | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Corner handles to resize | ✅ | ✅ | ✅ | 🟡 | ✅ |

Inside **Edit annotations**: tap to select, then drag to move, or drag a corner
to resize. Ink and stamps keep their aspect ratio; rectangles, ovals and lines
resize freely.

Text markup cannot be moved — `/QuadPoints` are anchored to the words they
cover. Sticky notes move but do not resize, because every viewer draws a
`/Text` icon at a fixed size. A stamp can be moved even though it cannot be
restyled: moving needs no understanding of what the annotation is.

## SP-4a — Watermarks

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Text watermark on every page | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Size, colour, opacity, rotation | ✅ | ✅ | ✅ | 🟡 | ✅ |

A watermark is **page content**, not an annotation — that is the difference
between it and a stamp, which any viewer can delete. It applies to every page
and produces a new document; your original is untouched as always.

Drawn with the non-embedded standard-14 Helvetica, so no font data is shipped.

## SP-5b — Password protection

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Protect a document with a password | ✅ | ✅ | ✅ | 🟡 | ✅ |

AES-256, the PDF 2.0 standard security handler (revision 6). The protected
document is a **new** document; your original stays as it was.

Folio cannot recover a protected document without its password. There is no
back door and no reset — that is what makes it protection.

## SP-5c — Owner password and restrictions

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Restrict printing, copying, changing, commenting | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Separate owner password | ✅ | ✅ | ✅ | 🟡 | ✅ |

Under **Protect with password → Restrict what readers can do**. Restrictions
are folded away by default, because most people protecting a document want it
unreadable rather than partly readable.

**Restrictions are advisory.** They are recorded in the document, most readers
honour them, and any reader is free to ignore them. Folio says so in the
dialog rather than implying a guarantee it cannot make. The password is the
part that actually protects the document.

The owner password opens the document with every right, ignoring the
restrictions. Leave it empty and the reader password does both jobs — a
restriction nobody can lift restricts the author too.

## SP-5d — Redaction

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Remove content under a drawn box | ✅ | ✅ | ✅ | 🟡 | ✅ |

Under the annotate menu → **Redact**. Drag a box over anything that should go,
tap a box to remove it, then **Apply redactions**. Nothing is written until the
confirmation is accepted, and the result is a new document.

**This removes the content; it does not cover it.** The bytes are gone from the
output file — not hidden under a rectangle, not sitting in an earlier revision.
Folio proves this on every build: the test suite redacts a token, inflates every
compressed stream in the result, and searches for it.

The way it works has consequences worth knowing before you rely on it:

- **The redacted page becomes an image** at 200 DPI. Text on that page is
  rebuilt as an invisible layer so search and selection keep working, but the
  page is no longer vector art.
- **The rebuilt text is approximate.** It uses the standard-14 Helvetica, so
  characters outside WinAnsiEncoding — CJK, Devanagari, most emoji — stay
  visible in the image but drop out of the searchable layer.
- **Metadata is not redacted.** A name in the title or author field survives.
  Folio says so in the confirmation rather than leaving you to find out.
- **Bookmarks and attachments are not redacted** either.

Pages you did not draw on are untouched, and render pixel-identically.

## SP-6a — Scanner

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Photograph pages into a PDF | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Import existing images into a PDF | ✅ | ✅ | ✅ | 🟡 | ✅ |

The scan icon in the library. Take photos or import images, reorder and remove
pages, then save as a new PDF.

**A scan has no text layer.** It cannot be searched, and its text cannot be
selected or copied. Folio says this on the scanner screen itself, before you
save, because Folio is now the thing producing such documents. OCR would fix
it and is not built — see below.

Pages are stored as the JPEG the camera produced, embedded untouched. A
ten-page scan is the size of ten photographs rather than of ten bitmaps.
Progressive JPEGs are refused rather than written into a file that some readers
render as garbage.

## SP-6b — OCR

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Make a scan searchable | ✅ | ✅ | ✅ | ❌ | ✅ |
| Search highlights land on the word | 🟡 | 🟡 | ✅ | ❌ | — |

Annotate menu → **Make searchable (OCR)**. Folio reads the words on each page
and adds an invisible text layer, so the document becomes searchable and its
text can be selected and copied. The picture is untouched — not one pixel
changes.

Runs entirely on the device. Nothing is uploaded, and it works with no network
at all.

**Accuracy of position differs by platform, and Folio does not pretend
otherwise.** On Android, Folio gets word boxes and places each word exactly
where it appears, so a search highlight lands on the word. On iPhone and iPad
the OCR engine can report the words but not their positions, so lines are
placed by reading order: search still finds the text and copying still works,
but a highlight shows the right area rather than the exact word.

**Not available on Windows.** The OCR engine Folio uses has no Windows
implementation, and the menu entry is disabled there rather than failing when
tapped.

English only. The bundled language model is 3.9MB.

## SP-7a — Compression

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Compress a document losslessly | ✅ | ✅ | ✅ | 🟡 | ✅ |

Annotate menu → **Compress**. Folio checks what it can save and tells you before
doing anything: *"Can save 340 KB (12%)"*, or that the document is already well
compressed and there is nothing worth doing.

**Nothing is removed and no image quality is reduced.** Three exact
transformations: identical objects are stored once, objects nothing refers to
are dropped, and streams left in the clear are deflated. Every page renders
pixel-identically afterwards, which the test suite asserts on every build.

**What it saves depends entirely on the document**, and Folio measured real
ones rather than guessing:

| Document | Saved |
|---|---|
| A merged set of five bank statements | **37%** |
| A single bank statement | 4% |
| A 1.6MB notification | 3% |
| A scanned document | 2% |
| A 3.6MB photographed passport scan | **0%** |

Merged documents gain the most, because merging duplicates every shared font
and image — and Folio's own merge feature produces exactly that. Scans and
photographs gain almost nothing, because their bytes are already compressed
images. Folio says so instead of offering a button that appears to do nothing.

**Folio will not reduce image quality to make a file smaller.** That is what
most apps mean by "compress", and it is lossy — see LIMITATIONS.

## SP-8a — Batch

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Apply one operation to many documents | ✅ | ✅ | ✅ | 🟡 | ✅ |

Select documents in the library, then the batch button. Four operations can be
applied to many documents at once: **Compress**, **Make searchable (OCR)**,
**Watermark** and **Protect with password**.

Redaction and page editing are deliberately absent. They need boxes or page
numbers chosen against each individual document, and quietly applying one
document's choices to another would be worse than not offering it.

**A batch always runs to completion.** One document that fails does not abandon
the rest, and the result says exactly what happened: *"7 done, 3 skipped — 2 had
nothing to gain · 1 could not be processed"*. A batch that stopped at the first
error would leave you with some documents processed and no record of which.

**Skipped is reported separately from failed.** A document that was already well
compressed had nothing to gain — that is information, not an error, and lumping
the two together would train you to ignore the errors.

**Stop actually stops**, and everything already finished stays. Cancelling does
not undo completed work.

Each result is a new document; your originals are untouched, as everywhere else
in Folio.

## SP-8b — Automation

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Rules that run when a document is added | ✅ | ✅ | ✅ | 🟡 | ✅ |

The automation button in the library. A rule runs when you add a document, and
can be narrowed by name or by minimum size. Three actions: **compress**, **make
searchable**, **watermark**.

**Compressing and OCR replace the document rather than making a copy.** Both are
lossless — nothing you can see changes — so an "auto-compress on import" rule
leaves you with one library entry, not two. Watermarking always makes a new
document, because it changes what the page looks like and replacing would
destroy the unmarked version.

**A document you opened in place is never rewritten.** That points at your own
file on disk; automation makes a new document for those instead.

**Protecting with a password cannot be automated,** and this is deliberate. A
rule that ran unattended would have to store your password to use it — turning
the one feature whose value is that Folio *cannot* recover your password into
one where Folio keeps it. The automation screen says so rather than leaving you
wondering why the option is missing.

**A failing rule never loses your import.** The document is in the library
first; rules run after, and one that fails is abandoned while the rest continue.

## SP-9 — Printing and sharing

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Print a document | ✅ | ✅ | ✅ | 🟡 | ❌ |
| Share a document | ✅ | ✅ | ✅ | 🟡 | ❌ |

In the viewer's menu. Print hands the document to your operating system's print
dialog; Share opens the system share sheet.

**These are the only two features in Folio where a document leaves your
device**, and the Offline column says ❌ for exactly that reason. Everything else
Folio does — reading, annotating, signing, encrypting, redacting, OCR,
compression — runs locally with no network. Printing sends the whole document to
a printer, which may be on your network or somewhere further; sharing hands the
file to another application, after which Folio has no say in what happens to it.

**The document is handed over unchanged.** Folio does not re-render or re-encode
it to print: what reaches the printer is the document in your library.

**Folio names what it is sending.** Every operation leaves the original
alongside the result, so a redacted document and its unredacted original sit in
the library with similar names — and sharing the wrong one is the realistic
mistake. The share sheet carries the document's own name, and Folio says which
one is going.

**A protected document cannot be printed.** Your operating system's print
renderer would need the password, which Folio does not hand over and could not
hand over safely. Folio refuses in the app rather than letting the job fail
inside the print service where nothing explains why. Sharing a protected
document works normally — it stays encrypted on the way out.

No print-range or scaling options: every platform's own print dialog already
offers both, and a worse duplicate would be worse than none.

## Removing a watermark

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Remove a watermark **Folio applied** | ✅ | ✅ | ✅ | 🟡 | ✅ |

Actions → **Remove watermark**. The page comes back exactly as it was before
the mark was applied — the test suite asserts pixel-identical on every page.

**Folio can only remove its own watermarks, and says so.** It names the
resources it adds, which is what lets it find them with certainty. A mark
another application added leaves no such marker, and deciding which parts of a
page's drawing instructions belong to it is the same problem as redaction, with
no reliable general answer.

This is not a guess about other tools. Eighteen real PDFs were examined for the
signals a watermark is supposed to leave — transparency groups, rotated
placements, optional-content groups, `/Artifact` marks, the words themselves —
and none carried any of them. There was nothing to build a detector against and
nothing to test one on, so Folio refuses that case with an explanation instead
of shipping heuristics that cannot be verified.

The removal is a full rewrite, not another appended update: the watermark's
objects are dropped from the file rather than merely stopped from drawing.

## Photographed signatures

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Photograph a signature and place it | ✅ | ✅ | ✅ | ❌ | ✅ |

The camera button in the signature sheet. Sign on white paper, photograph it,
and Folio removes the paper and keeps the ink.

**The photograph is never stored.** What is kept is the extracted ink. A photo
of your signature is also a photo of your desk, and Folio has no business
holding onto it.

**How the paper is removed.** A luminance histogram and Otsu's 1979 threshold —
classical image processing, no model, no training, no network. "Remove the
background" usually means a hosted segmentation service; this runs on your
device like everything else Folio does.

You see the result before saving it. Separating ink from paper is a judgement
the algorithm can get wrong, and you can tell at a glance far better than any
threshold can. A photo too dark to separate is refused with an explanation
rather than becoming a black rectangle on your contract.

**Not available on Windows**, because it needs the camera and gallery picker
that has no Windows implementation — the same reason OCR is unavailable there.

## Editing text on a page

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Change words already on a page | ✅ | ✅ | ✅ | 🟡 | ✅ |

Actions → **Edit text**. The words that can be changed are highlighted; tap
one, type, and the page is rewritten with everything else exactly where it
was.

**Layout is preserved, not reflowed.** The replacement is written in the run's
own font and the difference in width is absorbed by a kerning adjustment, so
the text after it does not move. That is what editing a total or a date needs;
it is not a word processor, and it does not re-wrap paragraphs.

**What it refuses, and why each refusal is useful:**

- **A character the font does not have.** A document carries only the glyphs
  it uses, so a page numbered "900 of 902" has no 3, 4, 5 or 6 in that font.
  Folio names the characters rather than saying it failed.
- **A replacement that would run into the text after it**, reported in points.
- **Text in a font that does not declare its widths.** Nothing can be refitted
  without them, so those words are shown greyed out rather than accepting a
  tap and then refusing whatever is typed.

  This is the commonest reason a whole document is uneditable. A PDF may use
  Helvetica, Times or Courier without carrying their measurements at all,
  leaving the reader to supply them from its own copy - and Folio has no copy.
  Measured across sixty real documents: 38 fully editable, 7 held back by
  exactly this, and the rest by structures Folio does not read.
- **Invisible text** — the layer OCR puts under a scan. Changing it alters
  nothing anybody can see.
- **Bytes Folio cannot read**, which it will not guess at.

Words that cannot be edited are still shown, in a quieter style. Hiding them
would leave you tapping at a word and getting nothing, unable to tell whether
you had missed it or it was fixed.

## Converting to Office

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| PDF to Word (.docx) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| PDF to Excel (.xlsx) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| PDF to PowerPoint (.pptx) | ✅ | ✅ | ✅ | 🟡 | ✅ |

Actions → **Convert to Office**.

**The text is converted, not the layout.** A PDF records where letters sit, not
that they form a paragraph - so paragraphs, columns and tables are inferred
from spacing and alignment, and some documents come out differently from how
they look. The sheet says this before you choose a format, not after.

- **Word** keeps the page size and puts a page break between pages. Paragraphs
  are inferred from the gaps between lines and from indentation.
- **Excel** gives one sheet per page, one row per line, and splits cells where
  the spacing is much wider than the spacing elsewhere on the page. It makes
  sense for a document that is a table; on anything else you get one column,
  which is honest but not useful.
- **PowerPoint** is the weakest, and modest on purpose: one slide per page with
  the text in a single box. Nothing resembling the original design is
  attempted, because a PDF does not record one.

A scan has no text until it has been through OCR, and Folio says so rather
than handing over an empty document.

The archive is written here rather than by a package: every Office format is
XML inside a ZIP, and a malformed archive gives a file Word refuses to open at
all. The tests read it back with a reader written from the specification and
hand the same bytes to Python's `zipfile` - an implementation nobody here
wrote, and one that cannot share a misunderstanding with this one.

None of which is Word. A converted document has been opened in **Word, Excel
and PowerPoint themselves** (Microsoft 365 on macOS, 2026-08-28): all three
opened it with no repair prompt and the text intact. `docs/RELEASE.md` has the
procedure for repeating that.

**Office to PDF is not built**, and is a much larger job: it means laying out
a document rather than reading one - line breaking, tables, sections, and
fonts that must be measured to be placed.

## Fonts

Folio **carries the font it draws with**. Page numbers, and in time every
other piece of text Folio adds, are written in Noto Sans, embedded into the
document as a subset.

Why it matters:

- A PDF that names a font it does not carry renders in whatever the reader
  substitutes. The same document looks different on every machine.
- **PDF/A refuses such a document outright**, which is why a numbered scan
  could not be archived before and can be now.
- The standard fourteen fonts cover Latin-1 and nothing else. **The rupee sign
  is not in Latin-1.** Folio writes text as glyph indices, two bytes each, so
  any character the font has can be written.

Only the glyphs actually used are embedded — a page number adds a few
kilobytes, not half a megabyte. Every embedded font carries a map back to
characters, so the text can still be selected, copied, searched and extracted.

Noto Sans is used under the SIL Open Font License 1.1; the licence travels
with it in `assets/fonts/`. Liberation Sans would have been the tidier choice,
being metric-compatible with Helvetica — but it has no rupee sign.

## Archiving (PDF/A)

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Save as PDF/A-2b | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Say why a document cannot be | ✅ | ✅ | ✅ | 🟡 | ✅ |

Actions → **Save as PDF/A**. PDF/A is the format archives accept: a document
carries everything it needs to render, so it looks the same in fifty years.

Folio writes **PDF/A-2b**. Part 1 forbids transparency, which would rule out
every document carrying a signature or an image watermark; level A needs a
tagged structure tree that cannot be inferred from a scanned page.

The colour profile is **built rather than shipped** — an sRGB ICC v2 profile
constructed from the published primaries and transfer function, so there is no
third-party binary to license or to trust.

Conversion is a full rewrite, not an appended revision: an archival file should
be one document, not a document plus every revision it passed through.

**What it refuses, and why that is the point.** PDF/A requires every font used
to be carried inside the file. Folio embeds no font programs, so a document
that names a font it does not carry cannot be converted — and the dialog names
the fonts rather than saying it failed. A file wrongly stamped PDF/A is worse
than one honestly refused, because the stamp is exactly what an archive trusts.

Documents with no fonts convert — which is most scans, and scanning is what
archiving is usually wanted for.

**What it removes**, listed in the dialog before you agree: embedded
JavaScript, attached files, and the request for a reader to redraw form fields.

## Forms

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Fill AcroForm fields | ✅ | ✅ | ✅ | 🟡 | ✅ |

Actions → **Fill form**. Text fields, checkboxes, radio groups and dropdowns,
with the document's own length limits and required marks.

Folio **generates the appearance itself** rather than setting
`/NeedAppearances` and asking the reader to draw the value. Readers that
honour that flag disagree about how; readers that ignore it show a blank
field; printing frequently shows neither. The value is there because Folio put
it there.

A choice field stores the export value and shows the label — you pick *India*,
the form's owner reads `IN`.

Shown but not filled:

- **Read-only fields**, because a read-only field is information the form is
  giving you. Hiding it loses that.
- **Signature fields**. A `/Sig` field promises a cryptographic signature;
  Folio can place a drawn signature on the page instead.

Two limits, said out loud on the screen rather than discovered afterwards:
**field scripts do not run**, so a total that calculates itself in another
reader will not recalculate here; and **XFA forms are refused**, because their
fields live in an XML payload the PDF page only stands in for.

Filled fields stay editable until you **flatten** — which is usually how a
filled form should leave the app.

## Flattening

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Flatten annotations | ✅ | ✅ | ✅ | 🟡 | ✅ |

Actions → **Flatten annotations**. Notes, drawings, stamps and signatures
become part of the page: they can no longer be selected, moved or deleted, in
Folio or anywhere else. Your original stays in the library.

Appearance streams are reused rather than re-rendered — an annotation's
appearance is already a form XObject, which is exactly what a page needs —
so nothing is re-encoded and nothing loses quality.

Three things are deliberately not flattened:

- **Links** keep working. A flattened link is a rectangle that goes nowhere.
- **Annotations with no appearance** are left alone. A form field whose value
  lives only in the annotation would otherwise vanish, which looks like
  flattening until someone needs the value.
- **Popups** are removed rather than painted. A popup is the note's open
  window, never part of the printed page.

When every field has been flattened, `/AcroForm` goes too — otherwise a
viewer draws its own empty fields straight back over them.

## Cropping

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Crop pages | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Detect margins | ✅ | ✅ | ✅ | 🟡 | ✅ |

Actions → **Crop pages**. Type a margin in millimetres for each side, or press
**Detect margins** to have Folio measure where the ink stops.

Detection reads the page's own paper colour rather than assuming white. A
scan's background sits around 210-240 — grey platen, JPEG noise, aged paper —
and measuring against white finds the whole page to be content, so exactly the
documents that most need trimming would report no margins at all.

Where pages disagree, the **smallest** margin wins. A trim that suits a sparse
page would cut into a full one.

Rotation is taken into account: on a page with `/Rotate 90`, the edge you see
as the top is the `/MediaBox` left edge, and cropping without that correction
trims the wrong side of every rotated scan — convincingly.

**Cropping hides the margins; it does not delete them.** The text is still in
the file and still extractable. Use redaction to remove content for good.

## Page numbers

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Number the pages | ✅ | ✅ | ✅ | 🟡 | ✅ |

Actions → **Number pages**. Choose the format — `7`, `Page 7`, `7 of 12`,
`Page 7 of 12` — a corner, and whether to start somewhere other than one.

**Leave the first page unnumbered** for a title page. The page after it then
reads "1", not "2": the numbering starts where the numbers start.

Numbers are page content, not annotations — the same choice watermarking makes.
A number any viewer can select and delete is not a page number.

## Exporting pages as images

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Export pages as images | ✅ | ✅ | ✅ | 🟡 | ❌ |

Actions → **Export pages as images**. Choose pages — `1-3, 7`, or leave it
empty for all — and a detail level, and Folio renders them and hands them to
the share sheet.

**PNG, not JPEG, and measured rather than assumed.** A 300 DPI A4 page of text
came out at 100 KB as PNG; at 96 DPI it is 25 KB. JPEG would be no smaller for
text and would smear the edges of every letter. `dart:ui` also encodes PNG
only, so choosing JPEG would have meant writing an encoder for a worse result.

The Offline column says ❌ because sharing is how the images leave — the
rendering itself happens entirely on your device.

## Not built yet

Accurate as of SP-10. Everything here is genuinely absent — nothing in this
list is shipped, and nothing shipped is in this list.

**Content creation (brief phase 7)** — the unfinished half of SP-4:

- **Adding text to a page.** Folio can annotate a page but cannot put a text
  box on it.
- **Adding an image to a page.** The foundations exist — Folio writes image
  XObjects for redaction and the scanner — but nothing exposes it.

**Metadata editing (phases 14–15).** `PdfMetadata` can already read a
document's title, author, subject and keywords, and `appendTo` can write them
— that is how metadata survives every operation. What is missing is any way for
you to *edit* them. There is no UI at all.

**Extensions of features that did ship:**






**Deliberate omissions, not gaps:**

- **Lossy image compression** — reducing a photograph's quality to shrink a
  file. See LIMITATIONS §6.
- **Protect with password as an automation rule** — it would require storing
  your password. See LIMITATIONS and the automation screen.

Freehand ink and shapes shipped in SP-3b, editing and deleting saved
annotations in SP-3c, drawn signatures in SP-3d, notes and stamps in SP-3e,
moving and resizing in SP-3f, and watermarks in SP-4a.
