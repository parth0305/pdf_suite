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

## Not built yet

**Behind the object layer:** redaction, and compressing documents Folio did
not write. The object layer itself landed in SP-5a, so these are now a matter
of building them rather than of missing foundations.

**Independent of it:** scanner, OCR, printing and sharing, batch processing,
automation rules, metadata editing, image watermarks, photographed signatures,
custom and date stamps, and reshaping individual ink points.

Freehand ink and shapes shipped in SP-3b, editing and deleting saved
annotations in SP-3c, drawn signatures in SP-3d, notes and stamps in SP-3e,
moving and resizing in SP-3f, and watermarks in SP-4a.
