# Testing

## Suites

| Suite | Command | Requires |
|---|---|---|
| Unit | `flutter test` | nothing — runs on any CI runner |
| Integration | `flutter test integration_test -d <device>` | simulator, emulator or device |
| Licence audit | `dart run scripts/check_licenses.dart` | nothing |

Unit tests never touch PDFium or a real device. They inject `FakePdfEngine`,
which is what allows them to run on the Ubuntu and Windows CI runners that have
no simulator.

## Fixtures

Generated, not committed:

```bash
dart run scripts/make_fixtures.dart
```

Integration tests build their own fixtures **on device** using the same pure
builder, so no test data ships in release builds.

| Fixture | Purpose |
|---|---|
| `sample_3page.pdf` | text extraction, search (`PLATYPUS-TOKEN-42`) |
| `pages_{1,10,100,500,1000,5000}.pdf` | open time, render, navigation, memory |
| `scanned_no_text.pdf` | search finds nothing rather than failing |
| `encrypted_user_pw.pdf` | password flow (password `folio-test`) |
| `no_copy_permission.pdf` | copy restriction, opens without a prompt |
| `corrupt_truncated.pdf` | safe failure |
| `malformed_xref.pdf` | safe failure |
| `embedded_javascript.pdf` | JavaScript must not execute |

## Current status

Last measured on 2026-08-27, after SP-5a.

| Platform | Result |
|---|---|
| Unit (host) | 591 passing |
| iOS simulator (iPhone 16 Plus, iOS 18.6) | 100 passed, 1 skipped |
| Android emulator (API 35, x86_64) | 99 passed, 2 skipped |
| Windows | **unit and build only — no integration tests, no manual QA** |

Skipped tests are platform-contract differences, not failures: iOS skips the
Android SAF-URI contract, and Android skips the two filesystem-path handle
tests that cannot apply there.

## Wait for a signal, never for a duration

`pumpAndSettle(Duration)` takes the pump **interval**, not a timeout. It
settles as soon as no frame is scheduled, which on a slow device happens long
before an async document load has finished.

Five pages-mode tests hoped a document would load within
`pumpAndSettle(const Duration(seconds: 3))`, then tapped a button that stays
disabled until the page count arrives. On a degraded emulator the tap hit a
disabled button and did nothing — a failure that looked like a regression from
an unrelated slice.

`pumpUntilFound` in `fixture_helper.dart` waits for the widget the load
actually produces, with a 30-second pathology bound. Note the finder matters:
`find.byIcon` matches a **disabled** button too, so waiting for the icon proved
nothing. Waiting for the page indicator — which only appears once the page
count is known — is what made it deterministic. The Android suite went from 22
minutes to 1:39.

**And the page indicator is not always late enough.** The viewer's search
button waits for the *searcher*, which arrives after the page count. Waiting
for the indicator got the document loaded but still tapped a disabled button.
`pumpUntilEnabled` waits for the `IconButton` wrapping a given icon to have a
non-null `onPressed` — tappability, not presence. Use it whenever a test taps a
toolbar button whose enablement depends on async work.

**A mutation has to be OBSERVABLE to prove anything.** The object layer's
round-trip test asserts zero pixels differ. The first mutation tried against it
— dropping the last object — did not fail, which looked like a blind
assertion. It was not: the last object is the Helvetica font, and PDFium
substitutes standard-14 fonts, so removing it changes nothing on screen.
Dropping the content streams instead fails at 7,308 pixels. When a mutation
does not fire, establish whether the assertion is blind or the mutation is
invisible before changing either.

**The fixture decides what an end-to-end test can see.** SP-5a's encryption
flow asserts an encrypted document renders identically. Mutating the writer to
leave dictionary strings unencrypted did **not** fail it — `sample_3page.pdf`
has no literal strings in its dictionaries, so the leak is invisible there. The
unit test caught it; the end-to-end one could not. A second assertion using
`with_metadata.pdf`, which carries `/Title` and `/Author`, now fails on exactly
that mutation. When choosing a fixture, ask what it makes observable.

**Some properties resist mutation testing, and saying so beats pretending.**
SP-5b guards two things about AES initialisation vectors: that `aesEncrypt`
prepends the IV it is given, and that identical plaintexts inside one document
produce different ciphertext. Neither could be made to fail by a mutation that
fixes the IV, and no render assertion can ever see IV reuse - a repeated IV
still decrypts correctly, so the document looks perfect. The tests are worth
having; they are not proven guards, and this note exists so nobody later
assumes they are.

**When the bound fires, suspect the machine before the bound.** A long session
degraded the emulator to the point where opening a 1,539-byte PDF took 31,256
ms; the same load takes about 50 ms fresh. `pumpUntilFound` timed out and the
run took over twelve minutes. Cold-restarting the emulator brought the whole
suite back to 53 seconds with zero failures and page loads of 124–241 ms. Do
not raise a pathology bound to accommodate a sick machine — that is exactly the
signal it exists to give.

## The runner's own timeout is a benchmark too

Integration suites carry `@Timeout(Duration(minutes: 5))`. The runner's default
is 30 seconds per test, which is a benchmark: on a loaded emulator, in the
aggregate run where one app process has already been alive for six minutes, a
loop over six stamp presets legitimately exceeds it.

Two tests failed that way on Android while passing in isolation on the same
emulator. The `Can't re-open a database after closing it` error that followed
was not a second bug — it is the timed-out test's async work continuing after
`tearDown` closed the database.

Five minutes means something is genuinely wrong, which is the only thing a
timeout should assert. Do not tighten it.

## Running the integration suite

```bash
flutter test integration_test/all_tests.dart -d <device-id>
```

Use the aggregate entrypoint, not the directory. `flutter test integration_test`
treats every file as its own Dart entrypoint and reinstalls and relaunches the
app once per file; on iOS that was 6:46 against 2:19 for the same 65 tests.
Run a single file directly when you want it in isolation.

## Coverage

```bash
flutter test --coverage
```

Business-logic coverage (`lib/domain` + `lib/data`, excluding generated
`*.g.dart`) is **85%** against a target of 80%. The SP-2a editing layer
(`lib/domain/editing`) is at **99%** against its own 90% target, which is
reachable because it is pure Dart with no native dependency.

Two files are deliberately low and are covered by integration tests instead:
`platform_handles.dart` is a platform-channel adapter that only answers on a
real device, and `app_database.dart` is drift schema declaration.

## Timing assertions are pathology bounds, not benchmarks

The integration suite contains a few wall-clock assertions on opening and
rendering large documents. They are deliberately generous: they exist to catch
an algorithm going quadratic, not to measure performance.

Tight thresholds here produce false failures. A 2000ms bound on rendering page
750 of a 1000-page document failed at 2796ms on an Android emulator fourteen
minutes into a full run - a loaded emulator, not a regression.

Real performance measurement needs a stable device and a dedicated run. Do not
tighten these bounds to make them meaningful; move the measurement instead.

## Verifying a test actually tests something

A worked example from SP-3d. The end-to-end assertion that a two-stroke
signature leaves a gap between its strokes originally sampled a single pixel
column at the midpoint. It passed — and it still passed when the strokes were
deliberately joined, because the spurious joining line dipped below the
appearance stream's `/BBox` and was clipped away.

The fix was to make the instrument sensitive rather than to tune a threshold:
the strokes now meet at mid-height, so a joining line crosses open space, and
the assertion counts untouched columns across the whole gap. Measured on device,
68 of 74 columns stay untouched when correct and 0 when joined.

**A second worked example, from SP-3e: some instruments are blind by nature.**
The end-to-end test that every stamp preset renders was checked against a
deliberately narrowed 40pt box, which clips every label. It still passed — a
clipped label draws pixels just as a complete one does. Pixel counts cannot
detect clipping, so the box-sizing rule has its own unit test asserting that a
longer label gives a wider box. Knowing which assertion is blind to what is
worth more than adding another that is blind the same way.

**A third, from SP-3f: the fixture can hide the bug too.** The end-to-end
assertion that geometry follows a moved annotation took three attempts. The
first asserted on `/Rect`, which a restyle preserves either way. The second
asserted on the render — but a viewer maps the appearance `/BBox` onto `/Rect`,
so stale geometry still draws in the right place, and the whole justification
for the feature turned out to be wrong. The third reads the geometry back, and
uses an **ink** annotation: a `/Square`'s geometry *is* its `/Rect`, so a
rectangle fixture leaves the bug nowhere to live. Every version passed until
the last one.

**A fourth, from SP-4a: `contains` cannot count.** The assertion that a page's
existing `/Resources` survive a merge checked that both the page's font and
ours appear in the output. It passed against a writer that appended a **second**
`/Resources` — the original is still in the string, so a contains-check sees it,
while a PDF reader takes only one of the two. It now asserts there is exactly
one `/Resources` and one `/Font`, and fails 2-against-1.

**A fifth, from SP-5c: a caught mutation can present as a hung job.** Making
the writer send a `/Perms` that disagrees with the `/P` it wrote should fail
the permission-readback test. Instead it hung the whole file for five minutes.
PDFium treats a `/Perms` mismatch as tampering and rejects **every** password,
pdfrx retries `onPasswordRequired` until it succeeds or the callback returns
null, and every encryption test here handed back a correct password forever.
The tests were detecting the mutation; the callback was hiding the detection
behind a timeout.

Every password callback in the integration suite now gives up after one retry.
The rule: a callback that supplies a **correct** password must still be
bounded, because the failure it has to survive is the reader refusing a
password that is right.

**A sixth, from the watermark-compression follow-up: the assertion that
"compressed" means "smaller".** Wiring watermark streams through the shared
`pdfStreamBody` made every test pass and made the output file **27 bytes
bigger**. The helper compared deflated bytes against raw bytes and never
counted the ` /Filter /FlateDecode` it also had to write. Nothing in the suite
would have noticed: the streams really were compressed, the reader really did
inflate them, and every assertion was about the stream rather than about the
document.

The test that catches it compares the finished document against what it would
weigh with those streams stored raw. A compression feature has to be measured
on the artefact it claims to shrink, not on the part that shrank.

**A seventh, from SP-5d: compression can blind an assertion completely.** The
decisive redaction test searched the output file's raw bytes for the redacted
token, on the reasoning that text extraction alone could be fooled. A redacted
page's content stream is Flate-compressed, so that search could not see **any**
text in it — the assertion passed against a build that deliberately kept every
redacted character. It was measuring nothing at all.

The test now inflates every Flate stream before searching, and a companion test
proves that machinery works by finding the token in a document where nothing was
redacted. Without that premise check a broken inflater would make the whole
assertion hollow again, silently.

**An eighth, from the same slice: `diff() > n` proves the wrong thing.** The
assertion that a black box was painted compared the page before and after and
required more than 200 changed pixels. Rasterising a page changes thousands of
pixels by itself, so it passed against a build that painted no box at all. It
now samples the box's own centre and requires it to be black, plus a point
outside it that is not.

**A ninth, about mutation testing itself.** Three mutations in Task 4 appeared
not to fire, which read as three hollow tests. All three were **no-ops**:
`dart format` had wrapped the lines the `sed` targeted, so the file was never
modified and the same unmutated build was being re-run. A mutation result means
nothing until the mutation is shown to have changed the file. Every mutation in
this slice is now applied by a script that asserts its anchor exists and
compares the file afterwards.

**A tenth, from SP-6a: sometimes the reader is too forgiving to notice.**
Declaring `/DeviceRGB` for a single-component JPEG should produce a corrupt
image. PDFium renders it correctly anyway - libjpeg reads the component count
out of the JPEG itself and ignores what the dictionary claims. No render
assertion can catch that mutation, so the unit test asserting `/DeviceGray` is
the only guard. The integration test's comment says so, rather than leaving a
reader to assume it covers what it cannot.

This is the second property in the project with no observable failure, after
AES IV reuse. Both are still written correctly, because the next reader may be
less forgiving than PDFium.

**An eleventh, from SP-6b: two code paths, one of which no test could tell
apart.** OCR places words accurately on Android and approximately on iOS. Every
integration assertion — text extracted, pixels unchanged, source untouched —
passed identically whether the accurate path ran or not, because both produce
extractable text. Forcing Android onto the fallback was green.

The test that catches it measures the gap between two adjacent lines: real
positions keep neighbours adjacent, while the fallback spreads lines a quarter
of a page apart. That still was not enough — the gap is mirror-symmetric, so
removing the y-flip passed it upside-down. It now also asserts the title sits
in the top half of the page.

**A twelfth, and the same trap as SP-4a's:** the assertion that `/Info` is
carried into a new trailer used `contains` on the whole file. An incremental
update leaves the original bytes at the front, so the ORIGINAL `/Info` satisfies
it and the test passed against a writer that dropped it. It now reads only the
last trailer. Anything asserted about an incremental update's new trailer must
be scoped to that trailer.

**A thirteenth, from SP-7a: the fixtures did not contain the thing being
tested.** Compression's main mechanism is collapsing duplicate objects. Not one
generated fixture has a duplicated object, so mutating the remapping - the step
that repoints references at the survivor - was green across the entire
integration suite. The suite proved compression was lossless on documents where
compression did nothing. A fixture with a genuinely duplicated font now exists,
and that mutation fails against it.

Before assuming a fixture exercises a feature, check that the fixture contains
the condition the feature exists for.

**Two more properties the device cannot observe**, bringing the total to four
alongside AES IV reuse and the JPEG `/ColorSpace`:

- A `/Length` that describes the uncompressed payload should make a stream
  unparseable. PDFium recovers by scanning for `endstream` and renders
  correctly, so only the unit test catches it. Stricter readers are not
  promised to be as forgiving.
- Remapping references inside a stream's binary payload would corrupt an image
  while leaving the file structurally valid. Constructing a device fixture whose
  compressed image data happens to read as `6 0 R` is impractical, so the unit
  test - which does exactly that with plain bytes - is the guard.

**A fourteenth, from SP-8b: a test that could not tell "never attempted" from
"attempted and swallowed".** A watermark rule with no text is refused before it
runs. Removing that guard changed nothing observable: the null assertion throws
instead, and automation's catch-all swallows it, so the same rule produces the
same result either way. The guard is kept — relying on a thrown exception for
ordinary control flow means a malformed rule costs an exception on every import,
forever — and the code says plainly that no test distinguishes it.

That is the fifth property recorded as unobservable rather than papered over.

**A fifteenth, from SP-10: the documentation described messages that did not
exist.** Three localised strings — the OCR "positions are approximate" note, the
batch "stopped" message, and the share "this leaves your device" warning — were
written, cited in `FEATURES.md` and `ARCHITECTURE.md` as things the UI says, and
never wired to anything. `ARCHITECTURE.md` claimed the OCR fallback was
"labelled as one everywhere it appears: in the UI, in FEATURES.md, and in
LIMITATIONS.md". Two of those three were true.

`test/l10n/strings_are_shown_test.dart` now fails when a string is defined and
never referenced. It found two further orphans and three genuine duplicates of
messages already shown elsewhere. In a project whose documentation makes
specific claims about what the app tells you, an unused string is not a
harmless leftover.

**A sixteenth, also from SP-10: a checker with a window instead of a parser.**
The first accessibility audit searched 400 characters after each `IconButton(`
for a `tooltip:` and reported eleven unlabelled buttons. Nine had tooltips — the
attribute simply sat past the window's edge, because `icon:` often comes first
and wraps over several lines. Acting on that output would have meant "fixing"
nine controls that were already correct, and it would have hidden the two that
were genuinely wrong.

`test/widgets/controls_are_labelled_test.dart` balances parentheses and skips
string literals instead. It found exactly two real cases. A source check that
guesses at extent will tell you confident, specific, wrong things.

**A seventeenth, and the most expensive: the seam that makes code testable is
where the untested defect lives.** Folio shipped a scanner that **crashes on
iOS**. `image_picker` needs `NSCameraUsageDescription`, and iOS terminates the
app the instant the camera opens without it. Every scanner test passed, because
every scanner test uses a fake `ScanImageSource` — the interface introduced
precisely so the feature could be tested without a camera.

The suite was not weak here. It could not reach the defect by construction. The
same shape exists at `PlatformExport`, `OcrEngine` and `PlatformHandles`.

Where a boundary cannot be crossed in a test, assert the declaration behind it
instead: `test/platform/permission_declarations_test.dart` checks `Info.plist`
directly, and the release checklist verifies the built bundle rather than the
source, because a correct source file that fails to reach the bundle fails
identically.

A green suite proves nothing until a mutation makes it red. Two properties in
this codebase are asserted by deliberate mutation rather than assumption:

- Adding an `AppFailure` variant without a message must fail compilation with
  `non_exhaustive_switch_expression`.
- RC4 is checked against published test vectors, not merely exercised.
- The owner password and `/Perms` are verified by an independent implementation
  of ISO 32000-2 Algorithm 2.A in `test/domain/pdf/pdf_owner_password_test.dart`,
  which recovers the file key the way a reader does rather than re-reading what
  the writer wrote. Five mutations fire against it, including hashing the user
  password into `/O` and dropping `/U` from the owner hash.
- Redaction is proven by inflating every stream in the output and searching for
  the redacted token, not by extracting text. The rebuild half is proven
  separately by requiring a different word on the same page to still extract -
  without it, emitting no text at all would pass every removal assertion.
- Permission bits are read back through PDFium as a **raw integer**. pdfrx's
  own `allowsCopying`/`allowsPrinting` getters name bits 4 and 16 the reverse
  of ISO 32000-1 Table 22, so asserting through them would make a swapped-bit
  bug invisible. The restricted fixture is deliberately asymmetric for the same
  reason: denying everything passes even when two bits are swapped.

## 18. A test fixture whose defaults painted a pixel

`painted(width: 50, height: 50)` was meant to make a blank page. Its `right`
and `bottom` defaulted to `0`, so the loop `for (x = left; x <= right; x++)`
ran once and blacked out the pixel at the origin. "A blank page has nothing to
trim" was therefore asserting against a page with ink on it — and passing,
because a single corner pixel produced margins on two sides and the assertion
only looked at whether *any* margin existed.

The failure surfaced only when a second test needed a genuinely blank page.
Default arguments in a fixture builder are a claim about what the fixture is;
`right = -1` (paint nothing) is the honest default for a blank page.

## 19. Two boxes that a renderer cannot tell apart

The crop writer sets both `/CropBox` and `/MediaBox`. On device, mutating away
*either one* leaves every test green: PDFium reports the crop box when there is
one and the media box when there is not, so a page cropped by either route
renders identically. The reason for writing both is what happens in OTHER
software — printers and importers that read `/MediaBox` — which this project
has no way to observe.

Recorded rather than papered over. The unit tests assert both boxes explicitly,
which is the only place the distinction is real.

Unobservable on device, joining the earlier five: AES IV reuse, JPEG
`/ColorSpace`, a wrong `/Length`, stream-payload reference remapping, and the
unrunnable-rule guard.

## 20. Measuring ink against white

Margin detection first compared each pixel against a fixed threshold of 250,
with white-page fixtures that made it look right. A scan's background is not
white — grey platen, JPEG noise and aged paper all sit around 210 to 240 — so
on a real scan every pixel counted as ink and the detector reported nothing to
trim, on precisely the documents the feature exists for.

The synthetic fixture agreed with the code because both assumed the same thing.
The fix (measure against the modal tone of the page's outer edge, where a
margin is by definition) is pinned by a fixture at luma 210, and the mutation
"assume paper is white" now fails it.

## 21. Two draws of the same thing in the same place

Leaving a flattened annotation in `/Annots` — so the mark is painted into the
page AND still drawn by the annotation layer — passed every device test. The
two draws land on the same pixels, so the render is identical either way.

That mutation is not cosmetic: the whole claim of flattening is that the mark
can no longer be selected, moved or deleted. What decides that is the
annotation list, not the pixels. The device test now parses the output with the
same reader the move-and-resize feature uses and asserts the page has no
annotations left — with a premise check that it had one to begin with.

The general shape: when a feature's promise is about what a user can no longer
DO, a picture of the result cannot test it.

## 22. A render that cannot see the thing being rendered

Form filling generates an appearance stream so the value is visible in every
reader. The obvious device test — render the page and look for the value —
cannot test it: PDFium draws no widget appearance in EITHER annotation
rendering mode, so a filled document and an untouched one are pixel-identical.
The first version of the test asserted a difference of at least 100 pixels and
found zero, against code that was working correctly.

What does discriminate: flatten the filled document and render THAT. Flattening
paints the appearance into the page, and it only has something to paint if an
appearance was generated. The mutation "generate no appearance" now fails it.

The lesson is the inverse of #21. There, a picture could not test a claim about
what a user can no longer do. Here, a picture could not test a claim about
drawing — because the renderer under test declines to draw that layer at all.
Both times the fix was to find the observation the property actually reaches.

## 23. Flattened, or only looking flattened

`/AcroForm /Fields` still listed every field after flattening, so a document
whose fields had all been painted into its pages still declared itself a form —
and a reader that regenerates appearances would draw empty boxes over the
flattened values. Every pixel test passed, because the boxes are only drawn by
readers that do that.

The device test now reads the form back after flattening and asserts the
flattened field is gone from it while the one that could NOT be flattened
remains. That second half matters: a field holding a value with no appearance
to paint is deliberately kept, and a test that just asserted "no form left"
would have driven the code to delete it.

## 24. An absence obtained by catastrophe

The test for "conversion removes embedded JavaScript" asserted the output did
not contain `/JavaScript`. It passed. The output also did not contain
`/Type /Catalog`, because the removal matched any object *mentioning* a script
and the catalogue had the script inline in its name tree — so conversion was
deleting the document's root and producing a file with no pages at all.

Everything is absent from a document with no root. An assertion that something
is missing is only meaningful alongside one that the rest is still there, and
the test now checks the catalogue, a page and the output intent survive.

The fix distinguishes an object that IS a script from one that MENTIONS one, by
blanking nested dictionaries before looking.

## 25. A fixture that claimed what it did not have

`scanned_no_text.pdf` had no text and a `/Font` resource anyway, because the
builder added the font object unconditionally. Nothing noticed until PDF/A
conversion asked whether the document carried the fonts it declared and
correctly answered no — refusing to convert the one fixture that exists to
represent a scan.

The fixture, not the checker, was wrong: a scanned page has no font. Fixtures
make claims about what they are, and `omitText: true` was making a false one.

## 26. Present in the file, unreachable from the root

A device test read the converted bytes for `/GTS_PDFA1` and found it. Removing
the line that references the output intent FROM the catalogue left that test
green: the object was still written, just orphaned — and an output intent
nothing points at is not an output intent.

The test now walks the file the way a reader does: last trailer, `/Root`,
catalogue, and only then the objects it names. Both "not referenced" mutations
fail it.

## 27. The fixture already said what the test was looking for

The device test for page numbering asserted the extracted text contained
`1 of 3`. The fixture's own footer reads **"Page 1 of 3"**. The assertion had
never once depended on Folio drawing anything, and it stayed green through a
mutation that removed the entire `/ToUnicode` map — the one thing that makes
drawn glyphs readable as text.

It surfaced only because that mutation was expected to fail and did not.
Numbering from 900 gives "900 of 902", which the fixture cannot produce.

When a test asserts that output contains a string, check the input does not
contain it already.

## 28. Four paths the shipped font could not reach

The TrueType parser had four mutations survive at once: short glyph offsets
read without doubling, a width read past the metric array, a character map
segment's indirection measured from the wrong place, and font units not scaled
into the thousandths a PDF wants.

None was a weak assertion. Noto Sans is drawn on a 1000-unit grid (so the
scaling is arithmetically invisible), uses long offsets, carries a metric for
every glyph, and needs no indirection in its character map. Four code paths
existed and were never once executed.

The fix was a synthetic font built by the tests with the awkward choices made
deliberately — a 2048-unit grid, short offsets, a short metric array, and the
indirection placed in the SECOND segment, because in the first one the wrong
arithmetic gives the right answer.

## 29. A default that hides a requirement

`/CIDToGIDMap /Identity` is what the specification says the entry means when it
is absent, so removing it changes nothing a renderer does — the device
mutation survives and always will. It stays because PDF/A validators require
the entry to be *present*, which is a requirement no renderer enforces.

Unobservable on device, joining the earlier six.

## 30. An assertion that matched the wrong element

The PowerPoint test checked the presentation contained
`cx="7556500" cy="10693400"` — the slide size in English Metric Units. It
passed through a mutation that stopped converting points to EMU at all,
because `<p:notesSz>` carries the same two attributes with the same values,
and the assertion never said which element it wanted.

Naming the element (`<p:sldSz cx="..." cy="..."/>`) fixes it. When a document
format repeats an attribute across elements, matching on the attribute alone
matches whichever one happens to be right.

## 31. The only implementation whose opinion counted

Folio's Office archives were checked by a reader written from the
specification, and by Python's `zipfile`. Both agreed the files were correct.
Neither is Word.

Opening one in Word, Excel and PowerPoint found no fault - but that was not the
point. The point is that until it was done, "the archive is structurally
correct" was the strongest claim available, and it is a weaker claim than "it
opens", which is what a user actually needs. The two are not the same
sentence and should not have been reported as one.

`docs/RELEASE.md` now carries the procedure, because the check cannot run in
CI: the applications are not there.

## 32. The mutation that hung, and what it was hiding

A mutation of the content-stream parser made a sub-parser return where it
started. The tokeniser then looped forever, and the mutation run stopped
producing output at all - no pass, no fail, nothing.

The mutation was mine and artificial. The gap it exposed was not: nothing in
the parser guaranteed that a token consumes at least one byte, so any future
mistake of that shape would freeze on a document rather than fail on one. A
parser fed arbitrary files has to terminate on all of them.

That property is now stated - `tokensAdvance` - and asserted against a dozen
malformed streams and every stream in the fixtures. And the mutation runner
now uses a timeout, so a hang reports as CAUGHT rather than as silence: a run
that produces nothing looks exactly like a run that has not finished.

## 33. Two guards that could never fire

The same run reported two survivors that no test could have caught, because
the code was unreachable. A `%` is itself neither newline nor carriage return,
so a comment always consumes at least that byte and the empty-comment guard
was dead. And the whitespace after an inline image's `ID` only matters to a
reader that decodes the data; this parser holds the image as a span, so
skipping it changed nothing.

Both were written defensively and both read, to anyone later, as cases someone
had thought about and handled. They are gone. A mutation that survives is
usually a missing test; sometimes it is code that should not exist.

## 34. Two of six products that upright text never exercises

The matrix multiply had a mutation survive: its rows and columns swapped, and
every test still passed. Not a weak assertion - the tests exercise translation,
scaling, the graphics state, `Tm`, `Td`, `T*` and the rest, and all of them use
UPRIGHT text, where the `b` and `c` elements are zero and two of the six
products cancel. Swapped or not, the answer comes out the same.

The fix is a test of the multiply itself, on two matrices with no zeroes in
them, against six values worked out by hand. It is the same shape as the
synthetic font in #28: the real inputs are all comfortable, so the awkward one
has to be made deliberately.

Worth noting what this would have cost later. Element `a` is not read by
anything today; it becomes load-bearing the moment a run's WIDTH is measured,
which is the next slice. A wrong multiply would have shown up there as text
that overlaps by a little, on rotated pages only.

## 35. A guard against cost, which no assertion measured

A damaged `/ToUnicode` CMap can declare a range covering sixteen million
codes. The parser skips such a range; removing that guard left every test
green, because the map still contained the right answers for the codes the
tests asked about. It was merely also filling sixteen million entries first.

Nothing in the tests measured cost, and cost was the entire point of the
guard. The fix does not measure it either - it asserts the CONSEQUENCE: a
code the absurd range would have covered is not mapped. That is checkable in
microseconds and fails the moment the range is expanded.

When a guard exists to prevent work rather than to change an answer, find the
answer it does change.

## 36. Two units that cancelled out

The overlap check multiplies a width in thousandths of the text size by the
font size to get points, and compares that with the room available. Removing
the multiplication left every test green, because the replacement in the test
was so much longer that it overran the budget either way.

At twelve point the two answers differ by a factor of twelve. The test that
catches it is deliberately marginal: three characters replacing one, five
points of room. With the size, it overruns and is refused; without, it looks
like a one-point overrun and sails through - which in a real document is a
word printed on top of the next one.

A test built from an extreme case cannot see a factor. It has to be built from
a case near the boundary.

## 37. A public function tested only through its caller

`encode` refuses a string containing a character the font cannot write. Every
test went through the edit planner, which checks for missing characters FIRST
and returns before encoding - so the refusal inside `encode` was never reached,
and a mutation removing it survived.

The function is public and is called directly elsewhere. Being right only when
approached through one particular caller is not being right.
