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

## Ruled out, with reasons

**Format conversion** — PDF to and from Word, Excel, PowerPoint, ODF, HTML,
EPUB, RTF, TXT, CSV, Pages, HWP. About seventeen features on a typical
competitor's list, and they ship cheaply because a server runs LibreOffice.
On-device means bundling a document engine or writing a parser and renderer per
format. Folio is already 37 MB because PDFium and Tesseract are bundled. This is
the price of having no server, and it is a deliberate non-goal rather than a
backlog item.

**Request signatures** — uploading a document, emailing a link, tracking who
signed. It is a cloud service, and it contradicts `PRIVACY.md` directly.

**Anything AI** — chat with PDF, summarising, AI OCR, question generation.
Forbidden by the brief, and the reason `PRIVACY.md` can say what it says.

**Lossy image compression** — see `LIMITATIONS.md` §6.
