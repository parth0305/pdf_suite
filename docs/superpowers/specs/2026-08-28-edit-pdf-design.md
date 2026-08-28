# Editing text on a page — design

Changing words that are already on a page, rather than drawing new ones over
it.

## Why this is the hardest thing on the list

Every other feature Folio has adds to a page. This one changes what is there,
and a PDF is not built to be changed. There is no paragraph, no line, no word:
there are instructions that put glyphs at coordinates. "Edit the total" means
finding the instruction that drew it, understanding what it says, writing a
different one, and leaving everything else on the page exactly where it was.

The failure mode is the reason for the care: a document that **looks** edited
and is subtly wrong. Text that overlaps by two points, a digit in a font that
lacks it and silently draws nothing, a line that reflows and pushes a total
onto the next page. None of these looks like an error. All of them are worse
than a refusal.

## The four problems, in order

### 1. Reading the instructions

A content stream is a byte soup of operators and operands, and it has traps:
strings with nested brackets and octal escapes, names with `#` escapes, and
inline images whose binary payload can contain anything at all - including the
bytes that end it. A parser that tokenises an inline image's data will find
operators in a JPEG.

**Approach:** tokenise over the ORIGINAL bytes, recording each token's span
rather than its value. Re-emitting is then copying spans, and an edit changes
only the spans it touches. This is the same principle as the incremental
writers: change one thing, leave everything else byte-for-byte alone.

### 2. Knowing what a show operator says

`(48500) Tj` shows five bytes. Which characters those are depends on the
font's encoding: a standard one, a `/Differences` array, or a CMap for a
composite font. A subsetted font may map `A` to byte 3.

**Approach:** resolve the encoding where it can be resolved, and say plainly
where it cannot. A run whose bytes cannot be read as text is shown as
uneditable rather than guessed at.

### 3. Writing different text

The replacement has to be encoded in the SAME font, and the font must have
glyphs for it. A subset embedded for "Invoice 2026" has no `x` in it. Typing
one draws nothing - or draws a box - and neither is reported by anything.

**Approach:** check every replacement character against the font before
accepting the edit. When a character is missing, offer the two honest options:
keep the original font and refuse the character, or draw the whole run in
Folio's own embedded font, which changes how it looks but not what it says.

### 4. Not moving everything else

A shorter replacement leaves a gap; a longer one runs into what follows.

**Approach:** compensate. `TJ` takes an array of strings and numbers, where
the numbers shift the next glyph. Emitting `[(new) delta] TJ` puts everything
after the edited run back exactly where it was, for any width difference.
Layout is preserved rather than reflowed - which is right for editing a total
or a date, and is not a general word processor.

When the replacement is wider than the space before the next run, it will
overlap. That is detected and refused, with the amount by which it does not
fit.

## Scope

**In:** replacing the text of a single show operator, in place, with layout
preserved.

**Out, and said out loud:**

- **Reflowing a paragraph.** Folio does not know where the paragraph is - see
  the Office conversion, where paragraphs are inferred and sometimes wrongly.
- **Changing font, size or colour** of existing text. That is a different
  feature and a smaller one; this slice is about the words.
- **Editing text inside a Form XObject** that is drawn more than once. Editing
  it changes every place it appears, which is rarely what was meant.
- **Scanned pages.** There are no instructions to edit; OCR adds an invisible
  layer over an image, and editing that changes nothing visible.

## The slices

- **E-1 — the content-stream parser.** Tokenise and re-emit losslessly.
  Verified by round-tripping every stream in every fixture byte-for-byte, and
  by the inline-image trap specifically.
- **E-2 — finding the text.** Walk the operators tracking the text state, and
  report each run: what it says, where it is, which font and size, and whether
  it can be edited at all.
- **E-3 — making the change.** Re-encode, compensate the width, write the page
  back as an incremental update.
- **E-4 — the editor.** Tap a run on the page, type, see it change.

## Testing

The parser's contract is exact and so is its test: for every content stream in
every fixture, and for streams built to contain each trap, re-emitting the
tokens reproduces the input byte for byte. Anything less is a parser that
works on the documents it was tried on.

For E-3, the device tests must check the page still renders the same apart
from the edited words - and that the text extracts as the new text, since a
change that looks right and extracts wrong is the failure this feature exists
to avoid.
