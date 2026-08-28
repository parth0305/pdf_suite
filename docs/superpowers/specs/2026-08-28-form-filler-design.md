# Form filler — design

Filling an AcroForm: the fields a document already declares, given values, and
saved as a new document whose values are visible in every reader.

## Why this is a subsystem and not a slice

A form is a tree, not a list. Fields inherit `/FT`, `/Ff`, `/V` and `/DV` from
their parents; a radio group is one field with several widget children; a
field's name is the dotted path from the root; and the thing you draw on the
page (the widget) is often not the thing that holds the value (the field).
Every one of those is somewhere a naive implementation quietly does the wrong
thing to a real government form.

## Scope

**In:** text fields, checkboxes, radio groups, choice fields (combo and list),
read-only and required flags, `/MaxLen`, multiline text.

**Out, deliberately:**

- **Signature fields** are shown and left alone. Folio can place a drawn
  signature on a page already; a `/Sig` field promises a cryptographic
  signature, and half of that is worse than none.
- **JavaScript field actions** — calculation, formatting, validation scripts.
  Executing them is out of the question (no scripting engine, and the brief
  rules it out), so a calculated total simply will not recalculate. Said out
  loud in the UI rather than discovered.
- **XFA forms.** An XFA document's fields live in an XML payload, not in
  AcroForm; the PDF page is a "please open in Acrobat" placeholder. Detected
  and refused with an explanation, never half-filled.

## The three parts

### 1. Reading (slice F-1)

`FormReader.parse(pdfText)` walks `/AcroForm /Fields`, resolving inheritance,
and returns terminal fields with: qualified name, kind, current value,
options, flags, and the widgets that draw them — each widget with its page
index, rectangle, and its "on" state name where it has one.

A field's kind comes from `/FT` plus `/Ff`: `/Btn` is a pushbutton, a radio
group, or a checkbox depending on two bits, and confusing the three makes a
checkbox that cannot be ticked.

### 2. Filling (slice F-2)

`writeFilledForm(pdf, values)` appends an incremental update that sets `/V` on
each field, `/AS` on each widget of a button field, and **generates the
appearance stream itself**.

Generating appearances rather than setting `/NeedAppearances true` is the
decision that matters. `/NeedAppearances` asks the READER to draw the value;
readers that honour it disagree about how, readers that ignore it show a blank
field, and printing frequently shows neither. Folio already draws text into
form XObjects for stamps and watermarks. The value is visible everywhere,
including in print, because Folio put it there.

Appearance generation follows the field's own `/DA` (default appearance
string) where there is one, so a filled field matches the ones around it.

### 3. Filling in the app (slice F-3)

A form panel listing every field with the right control for its kind, and
tap-to-focus on the page. Read-only fields are shown and not editable —
hiding them loses information the form is trying to give.

## What flattening already did

`writeFlattened` handles widget annotations and removes `/AcroForm` once every
field is flattened. A filled form flattens with no further work, which is how a
filled form should usually leave the app.

## Testing

The fixture is a form built by `pdf_fixture_builder.dart` covering every kind
in scope plus a read-only field and a signature field. Device tests assert the
filled value is visible **with form rendering switched off** — the same test
shape flattening needed, and for the same reason: with forms rendered by the
viewer, a document that Folio never touched looks filled too.
