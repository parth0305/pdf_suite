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

## Not in SP-1 or SP-2a

Freehand ink, shapes, sticky notes, stamps, signatures, scanner, OCR,
compression, encryption authoring, redaction, watermarks, metadata editing,
batch processing, automation rules, and printing are all ❌ — planned for SP-2b through SP-9.
