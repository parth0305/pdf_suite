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

## Not built yet

Still absent: printing and sharing. Lossy image compression — reducing a photograph's quality to
shrink a file — is a deliberate omission rather than a gap.

**Independent of it:** printing and sharing, batch processing,
automation rules, metadata editing, image watermarks, photographed signatures,
custom and date stamps, and reshaping individual ink points.

Freehand ink and shapes shipped in SP-3b, editing and deleting saved
annotations in SP-3c, drawn signatures in SP-3d, notes and stamps in SP-3e,
moving and resizing in SP-3f, and watermarks in SP-4a.
