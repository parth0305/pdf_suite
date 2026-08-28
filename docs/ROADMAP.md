# Roadmap

What is agreed but not built. Ordered by value against effort, with the reason
each one is where it is.

Everything here is a deliberate list, not a wish list: an item is added when it
has been decided on, and removed when it ships or is ruled out.

## Office conversion

PDF to Word, Excel and PowerPoint has shipped. The other direction has not,
and calling them one feature would have been dishonest: one was hard work and
the other is a research project.

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
