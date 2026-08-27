# Roadmap

What is agreed but not built. Ordered by value against effort, with the reason
each one is where it is.

Everything here is a deliberate list, not a wish list: an item is added when it
has been decided on, and removed when it ships or is ruled out.

## Next

### Reshaping individual ink points
Moving and resizing a whole annotation shipped in SP-3f. Dragging one point of
a drawn stroke does not exist. The geometry is already read back and rewritten
per point, so the writer needs little; the work is the hit-testing and the
handles.

### PDF to JPG
Export pages as images. Folio already renders pages to pixels for redaction and
OCR, and already encodes PNG for the signature preview. Mostly plumbing plus a
page-range choice. **JPEG encoding is the open question** — `dart:ui` encodes
PNG only, so this either exports PNG, or bundles an encoder, or accepts larger
files. Decide before building.

### Number pages
A content stream per page with a number in it, drawn with the standard-14 font
that stamps and watermarks already use. Needs a position choice and a starting
number; "page 3 of 12" is a formatting decision, not an engineering one.

## After that

### Crop PDF
A `/CropBox` per page. The writing is small — the work is a UI for choosing the
crop and previewing it, and deciding whether one crop applies to every page.

**Nothing is destroyed by cropping**: `/CropBox` hides content rather than
removing it, so a cropped document still carries what was cropped away. That
must be said in the UI, because people crop to remove things.

### Flatten PDF
Merge annotations into the page's own content so they cannot be edited or
removed. The pieces exist: appearance streams are already generated, and the
content-merging is what watermarking does.

Flattening is irreversible in the output, which puts it in the same class as
redaction: it needs a confirmation that says so.

## Large, and not started

### Form filler
AcroForm fields, widget annotations, and regenerating each field's appearance
as it is filled. A real subsystem rather than a slice.

### Edit PDF
Changing text that is already on the page. This needs the content-stream
operator parser that redaction deliberately avoided, plus font metrics, plus
reflow. The single hardest item on this list, and the one whose failure modes
are least visible - text that looks edited but is subtly wrong.

### PDF/A
A compliance standard, not a feature: embedded fonts, colour profiles, XMP
metadata, and validation against the profile claimed. Folio currently embeds no
fonts at all, which is the first thing PDF/A would change.

## Office conversion — agreed, and the two directions are not one job

Added on request. They belong in the plan, but calling them a single feature
would be dishonest: one direction is hard work and the other is a research
project.

### PDF to Word, Excel and PowerPoint — feasible

Folio already has the hard half. PDFium reports **per-character rectangles**,
which is what OCR and redaction are built on, so the text and its positions are
in hand. The output formats are OOXML: XML inside a ZIP, and writing XML is
mechanical.

The honest limits, which should be said in the UI rather than discovered:

- **Layout is reconstructed, not preserved.** A PDF records where glyphs sit,
  not that they form a paragraph. Grouping characters into words, lines and
  paragraphs is inference, and it will get some documents wrong.
- **Excel only makes sense for tables**, and finding a table in a PDF means
  inferring one from alignment. A PDF has no notion of a cell.
- **PowerPoint is the weakest.** One slide per page with the text placed on it
  is achievable; anything resembling the original design is not.

It needs a **ZIP writer**, which Folio does not have. `dart:io` provides
deflate, so the container is a bounded piece of work rather than a dependency —
but it is new code that has to be right, because a malformed ZIP produces a file
Word refuses to open at all.

### Word, Excel and PowerPoint to PDF — much harder

This direction means parsing OOXML and **laying it out**: line breaking,
justification, tables, floats, sections, headers, and fonts that must be
measured to be placed. That is a word processor's layout engine, and it is why
every web tool runs LibreOffice on a server to do it.

Folio also embeds no fonts today. Rendering a document written in a font the
device does not have means either substituting one — changing the pagination
the author saw — or bundling fonts, which is megabytes each.

Not ruled out, but it should not be started until the other direction has
shipped and been used: PDF-to-Office will teach us how much layout fidelity
people actually expect.

## Ruled out, with reasons

**The remaining conversions** — ODF, HTML, EPUB, RTF, TXT, CSV, Pages, HWP.
Each is a separate parser for a separate format, and unlike Office they are not
what most people are asking for. Reconsider individually if asked; not planned.

**Request signatures** — uploading a document, emailing a link, tracking who
signed. It is a cloud service, and it contradicts `PRIVACY.md` directly.

**Anything AI** — chat with PDF, summarising, AI OCR, question generation.
Forbidden by the brief, and the reason `PRIVACY.md` can say what it says.

**Lossy image compression** — see `LIMITATIONS.md` §6.
