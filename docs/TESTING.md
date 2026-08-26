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

Last measured on 2026-08-26, after SP-4a.

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

A green suite proves nothing until a mutation makes it red. Two properties in
this codebase are asserted by deliberate mutation rather than assumption:

- Adding an `AppFailure` variant without a message must fail compilation with
  `non_exhaustive_switch_expression`.
- RC4 is checked against published test vectors, not merely exercised.
