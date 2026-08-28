# Roadmap

What is agreed but not built. Ordered by value against effort, with the reason
each one is where it is.

Everything here is a deliberate list, not a wish list: an item is added when it
has been decided on, and removed when it ships or is ruled out.

## Next

Measured over sixty real documents, editing works on 38 of them. What stops
the other 22, in order of how many it costs:

| Count | Cause | Verdict |
|---|---|---|
| 7 | A standard font whose widths the document does not carry | Fixable — see below |
| 5 | The page is an image | Correct. There is no text; OCR first |
| 4 | The document is encrypted | Already possible: remove the password first |
| 3 | The page dictionary is inside a compressed object stream | Fixable — object stream support |
| 1 | `/Annots` is an indirect reference | A bug: reading text should not care |
| 1 | The fonts give no way to read their bytes back | Correct to refuse |
| 1 | A composite font carrying no widths | Correct to refuse |

### The metrics of the fourteen standard fonts
Helvetica, Times, Courier, Symbol and Zapf Dingbats may be used by a document
without carrying their widths: a reader is expected to know them. Folio does
not, so it cannot refit text in them, and that is what stops 7 documents in 60
from being editable - the largest single cause.

The tables are public and fixed. They must be TRANSCRIBED rather than
estimated: a width that is close is worse than none, because the text after an
edit moves by the error and nothing reports it.

### Object streams
A PDF 1.5 file may keep its page and font dictionaries inside a compressed
`/ObjStm`, where scanning for `N 0 obj` finds nothing. Folio then reports a
document with no pages. Three in sixty, and it also blocks archiving and
editing anything in such a file.

### Reading text should not care how annotations are stored
`PdfObjectReader` refuses a document whose `/Annots` is an indirect reference.
That refusal is right for the annotation writers - merging into it would orphan
what it holds - and wrong for everything that only wants to read text. One
document in sixty fails for this reason alone.

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
