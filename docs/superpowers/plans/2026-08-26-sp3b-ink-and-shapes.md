# SP-3b Ink and Shapes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user draw freehand strokes, rectangles, ovals, lines and arrows onto any page — including scans — and save them into the PDF so any viewer can see them.

**Architecture:** Drawings are staged in the same `AnnotationSession` as text markup, which becomes generic over a sealed `Annotation` type. Canvas points are converted to PDF user space by a pure function derived from the page rect the paint callback supplies. Saving reuses SP-3a's incremental-update writer unchanged; this slice adds annotation *types*, not a pipeline.

**Tech Stack:** Flutter 3.41.9 · Dart 3.11.5 · pdfrx 2.4.7 · flutter_riverpod 3.3.2 — **no new dependencies**.

**Spec:** `docs/superpowers/specs/2026-08-26-sp3b-ink-and-shapes-design.md`

## Global Constraints

- **`PdfEngine` must not gain a write, save, or export method.** All writing goes through the annotation writer. Definition-of-Done checks this.
- **Zero AI. Zero network.** `test/offline_guarantee_test.dart` fails the build on a networking dependency, a network API in `lib/`, the Android `INTERNET` permission, or the macOS `network.client` entitlement.
- **No new dependencies.** Any addition must be MIT/BSD/Apache-2.0 and recorded in `docs/THIRD_PARTY_LICENSES.md` in the same commit.
- **Originals are never modified.** Saving produces a **new** library document; the source stays byte-identical, asserted by SHA-256.
- **Metadata must survive.** Saving goes through `DocumentWriter`; a path that skips it reintroduces the SP-2b data-loss bug.
- **No hard-coded user-facing strings.** ARB then `flutter gen-l10n`.
- **Layout branches on width class, never `Platform.isX`.**
- **`flutter analyze --fatal-infos` clean; `dart format` produces no changes.** Run the analyzer after every implementation step, not just the tests.
- **Minimum touch target 48x48dp; screen-reader labels on every interactive element.**

### Facts already established — do not re-derive

- SP-3a's write path is **merged and verified on both platforms**: `PdfObjectReader`, `pdf_annotation_writer`, `pdf_appearance`, `DocumentWriter`, `AnnotationRepository`. This slice reuses them.
- Annotations **render** through the production path, proven by pixel comparison on iOS and Android.
- `/AP` is generated even though PDFium does not require it, because portability is why annotations are written into the file and could not be measured here.
- The page paint callback is `void Function(Canvas canvas, Rect pageRect, PdfPage page)` — `pageRect` is the conversion key.
- **PDF's `/Circle` draws an ellipse inscribed in its `/Rect`**, not a circle. Three names are in play: `DrawingKind.ellipse`, PDF `/Circle`, user-facing "Oval".
- pdfrx's `PdfAnnotation` is **metadata-only** — no geometry, no subtype, no enumeration. Editing saved annotations cannot be borrowed from the engine and is out of scope.
- Cross-reference-stream documents are refused with `UnsupportedPdfStructure`.
- **The repository is public**, so GitHub Actions minutes are unlimited. Verify on all four CI jobs freely.

### Working agreements

- Fixtures are generated: `dart run scripts/make_fixtures.dart`. Integration tests build their own on-device via `integration_test/fixture_helper.dart`, from the same shared builder — **add new fixtures to both**; they have diverged before.
- iOS simulator `DFC5606D-37F0-4176-A73D-B8214C7F820F`; Android `flutter emulators --launch pixel_api35` then `-d emulator-5554`.
- Integration timing assertions are **pathology bounds, not benchmarks**. Do not tighten them.
- A green suite proves nothing until a mutation makes it red. Where this plan asserts a property, it says how to mutation-test it.

---

## File Structure

| Path | Responsibility |
|---|---|
| `lib/domain/annotations/pdf_point.dart` | `PdfPoint` value type |
| `lib/domain/annotations/page_coordinates.dart` | canvas ↔ PDF user space mapping |
| `lib/domain/annotations/stroke_smoothing.dart` | sample thinning + Bézier fitting |
| `lib/domain/annotations/annotation.dart` | sealed `Annotation` supertype |
| `lib/domain/annotations/drawing_annotation.dart` | `DrawingAnnotation`, `DrawingKind` |
| `lib/domain/annotations/drawing_appearance.dart` | `/AP` content streams for drawings |
| `lib/features/viewer/widgets/drawing_surface.dart` | gesture capture, live preview |
| `lib/features/viewer/widgets/drawing_toolbar.dart` | tool, colour, stroke width |

Modified: `text_markup.dart` (extends `Annotation`), `annotation_session.dart` (holds `Annotation`), `pdf_annotation_writer.dart` (emits drawing subtypes), `annotation_providers.dart`, `viewer_screen.dart`.

---

# Stage 1 — Pure domain

Runs on any CI runner. The coordinate mapping comes first because everything else depends on it being right.

---

### Task 1: PdfPoint and coordinate mapping

**Files:**
- Create: `lib/domain/annotations/pdf_point.dart`, `lib/domain/annotations/page_coordinates.dart`
- Test: `test/domain/annotations/page_coordinates_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `PdfPoint(double x, double y)` with value equality; `PdfPoint canvasToPdf(Offset canvasPoint, {required Rect pageRect, required double pageWidthPt, required double pageHeightPt})`; `Offset pdfToCanvas(PdfPoint point, {required Rect pageRect, required double pageWidthPt, required double pageHeightPt})`

Text markup received geometry free from `charRects`. Drawing does not. **A wrong y-flip puts every stroke upside down and looks entirely plausible in review**, so this is task one and it is tested by round trip.

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/page_coordinates_test.dart`:
```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/page_coordinates.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

/// An A4 page drawn at 1x: 595x842pt shown as 595x842 logical pixels at the
/// canvas origin.
const a4At1x = Rect.fromLTWH(0, 0, 595, 842);
const w = 595.0;
const h = 842.0;

void main() {
  group('canvasToPdf', () {
    // The whole point of this file. PDF y grows upward; canvas y grows
    // downward. Near the TOP of the page, PDF y must be LARGE.
    test('a point near the page top maps to a large PDF y', () {
      final p = canvasToPdf(
        const Offset(100, 10),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.y, greaterThan(800), reason: 'y-up: near the top means high y');
    });

    test('a point near the page bottom maps to a small PDF y', () {
      final p = canvasToPdf(
        const Offset(100, 832),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.y, lessThan(20));
    });

    test('the top-left canvas corner is the top-left of PDF space', () {
      final p = canvasToPdf(
        Offset.zero,
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.x, closeTo(0, 0.001));
      expect(p.y, closeTo(842, 0.001));
    });

    test('the bottom-right canvas corner is the PDF origin corner', () {
      final p = canvasToPdf(
        const Offset(595, 842),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.x, closeTo(595, 0.001));
      expect(p.y, closeTo(0, 0.001));
    });

    test('x is unaffected by the flip', () {
      final p = canvasToPdf(
        const Offset(300, 400),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      expect(p.x, closeTo(300, 0.001));
    });
  });

  group('round trip', () {
    void roundTrips(String label, Rect rect) {
      test('survives a round trip $label', () {
        for (final point in const [
          Offset(0, 0),
          Offset(1, 1),
          Offset(123.5, 456.25),
          Offset(300, 400),
        ]) {
          final canvas = Offset(
            rect.left + point.dx * (rect.width / w),
            rect.top + point.dy * (rect.height / h),
          );
          final pdf = canvasToPdf(
            canvas,
            pageRect: rect,
            pageWidthPt: w,
            pageHeightPt: h,
          );
          final back = pdfToCanvas(
            pdf,
            pageRect: rect,
            pageWidthPt: w,
            pageHeightPt: h,
          );

          expect(back.dx, closeTo(canvas.dx, 0.01), reason: '$label x');
          expect(back.dy, closeTo(canvas.dy, 0.01), reason: '$label y');
        }
      });
    }

    roundTrips('at 1x', a4At1x);
    roundTrips('at 2.5x zoom', const Rect.fromLTWH(0, 0, 1487.5, 2105));
    roundTrips('at 0.4x zoom', const Rect.fromLTWH(0, 0, 238, 336.8));
    // A page scrolled partly out of view has a negative origin.
    roundTrips('scrolled off-screen', const Rect.fromLTWH(-200, -350, 595, 842));
    roundTrips('offset and zoomed', const Rect.fromLTWH(37.5, -120, 892.5, 1263));
  });

  group('zoom independence', () {
    // The same physical spot on the page must yield the same PDF point at any
    // zoom, or strokes would land differently depending on how far you had
    // pinched in.
    test('the page centre maps identically at 1x and 2.5x', () {
      final at1x = canvasToPdf(
        const Offset(297.5, 421),
        pageRect: a4At1x,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      final at2x = canvasToPdf(
        const Offset(743.75, 1052.5),
        pageRect: const Rect.fromLTWH(0, 0, 1487.5, 2105),
        pageWidthPt: w,
        pageHeightPt: h,
      );

      expect(at2x.x, closeTo(at1x.x, 0.01));
      expect(at2x.y, closeTo(at1x.y, 0.01));
    });
  });

  group('PdfPoint', () {
    test('points with the same coordinates are equal', () {
      expect(const PdfPoint(1.5, 2.5), const PdfPoint(1.5, 2.5));
      expect(const PdfPoint(1.5, 2.5).hashCode, const PdfPoint(1.5, 2.5).hashCode);
    });

    test('points with different coordinates are not equal', () {
      expect(const PdfPoint(1, 2), isNot(const PdfPoint(2, 1)));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/page_coordinates_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement PdfPoint**

`lib/domain/annotations/pdf_point.dart`:
```dart
/// A point in PDF user space, where y grows **upward** from the bottom-left of
/// the page.
///
/// New in SP-3b: text markup only ever needed rectangles, so no point type
/// existed before drawing.
class PdfPoint {
  const PdfPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is PdfPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PdfPoint($x, $y)';
}
```

- [ ] **Step 4: Implement the mapping**

`lib/domain/annotations/page_coordinates.dart`:
```dart
import 'dart:ui';

import 'package:folio/domain/annotations/pdf_point.dart';

/// Converts a point in canvas space to PDF user space.
///
/// [pageRect] is where the page is currently drawn on the canvas, which is what
/// pdfrx's page paint callback supplies. It already encodes zoom and scroll, so
/// no separate zoom factor is needed.
///
/// Canvas y grows downward; PDF y grows upward. The flip is the entire reason
/// this function exists as a tested unit.
PdfPoint canvasToPdf(
  Offset canvasPoint, {
  required Rect pageRect,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final normalisedX = (canvasPoint.dx - pageRect.left) / pageRect.width;
  final normalisedY = (canvasPoint.dy - pageRect.top) / pageRect.height;

  return PdfPoint(
    normalisedX * pageWidthPt,
    (1 - normalisedY) * pageHeightPt,
  );
}

/// The inverse of [canvasToPdf], used to preview staged drawings on screen.
Offset pdfToCanvas(
  PdfPoint point, {
  required Rect pageRect,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final normalisedX = point.x / pageWidthPt;
  final normalisedY = 1 - (point.y / pageHeightPt);

  return Offset(
    pageRect.left + normalisedX * pageRect.width,
    pageRect.top + normalisedY * pageRect.height,
  );
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/domain/annotations/page_coordinates_test.dart`
Expected: PASS — 14 tests

- [ ] **Step 6: Mutation-test the y-flip**

In `canvasToPdf`, remove the flip: change `(1 - normalisedY)` to `normalisedY`. Run the suite.

Expected: `a point near the page top maps to a large PDF y`, both corner tests, and **every round-trip test** fail. Revert and confirm green. This is the defect that would have shipped strokes upside down.

- [ ] **Step 7: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: add PdfPoint and canvas/PDF coordinate mapping

Canvas y grows downward, PDF y grows upward. The flip is verified by round
trip at 1x, 2.5x and 0.4x zoom, on a page scrolled partly out of view, and by
an explicit assertion that a point near the page top maps to a large PDF y.

Mutation-verified: removing the flip fails every round-trip test. pageRect
already encodes zoom and scroll, so no separate zoom factor is needed."
```

---

### Task 2: Stroke smoothing

**Files:**
- Create: `lib/domain/annotations/stroke_smoothing.dart`
- Test: `test/domain/annotations/stroke_smoothing_test.dart`

**Interfaces:**
- Consumes: `PdfPoint` (Task 1)
- Produces: `List<PdfPoint> thinSamples(List<PdfPoint> raw, {double minDistance = 2.0})`; `List<CubicSegment> fitCurve(List<PdfPoint> points)` where `CubicSegment({required PdfPoint control1, required PdfPoint control2, required PdfPoint end})`

Raw touch samples are jagged and numerous. Thinning then Bézier fitting fixes both. **Preview and emitted path data must be generated from the same smoothed points**, or what the user drew and what gets saved will disagree.

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/stroke_smoothing_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/stroke_smoothing.dart';

void main() {
  group('thinSamples', () {
    test('an empty stroke stays empty', () {
      expect(thinSamples(const []), isEmpty);
    });

    test('a single point survives', () {
      expect(thinSamples(const [PdfPoint(10, 10)]), hasLength(1));
    });

    // A finger held still emits dozens of near-identical samples.
    test('samples closer than the minimum distance are dropped', () {
      final raw = [
        const PdfPoint(10, 10),
        const PdfPoint(10.2, 10.1),
        const PdfPoint(10.3, 10.2),
        const PdfPoint(30, 10),
      ];
      final thinned = thinSamples(raw, minDistance: 2);

      expect(thinned, hasLength(2));
      expect(thinned.first, const PdfPoint(10, 10));
      expect(thinned.last, const PdfPoint(30, 10));
    });

    // Losing the final point would visibly shorten every stroke.
    test('the last point is always kept', () {
      final raw = [
        const PdfPoint(0, 0),
        const PdfPoint(50, 0),
        const PdfPoint(50.5, 0),
      ];
      expect(thinSamples(raw, minDistance: 5).last, const PdfPoint(50.5, 0));
    });

    test('widely spaced samples are all kept', () {
      final raw = [
        const PdfPoint(0, 0),
        const PdfPoint(20, 0),
        const PdfPoint(40, 0),
      ];
      expect(thinSamples(raw, minDistance: 2), hasLength(3));
    });
  });

  group('fitCurve', () {
    test('fewer than two points produce no segments', () {
      expect(fitCurve(const []), isEmpty);
      expect(fitCurve(const [PdfPoint(1, 1)]), isEmpty);
    });

    test('two points produce one segment ending at the second', () {
      final segments = fitCurve(const [PdfPoint(0, 0), PdfPoint(10, 0)]);

      expect(segments, hasLength(1));
      expect(segments.single.end, const PdfPoint(10, 0));
    });

    test('n points produce n-1 segments', () {
      final segments = fitCurve(const [
        PdfPoint(0, 0),
        PdfPoint(10, 10),
        PdfPoint(20, 0),
        PdfPoint(30, 10),
      ]);
      expect(segments, hasLength(3));
    });

    // The endpoints are what the user actually touched; they must not move.
    test('the curve ends exactly on the final point', () {
      const points = [PdfPoint(0, 0), PdfPoint(10, 20), PdfPoint(35, 5)];
      expect(fitCurve(points).last.end, const PdfPoint(35, 5));
    });

    test('a straight horizontal drag stays straight', () {
      const points = [PdfPoint(0, 0), PdfPoint(10, 0), PdfPoint(20, 0)];

      for (final segment in fitCurve(points)) {
        expect(segment.control1.y, closeTo(0, 0.001));
        expect(segment.control2.y, closeTo(0, 0.001));
        expect(segment.end.y, closeTo(0, 0.001));
      }
    });

    test('control points lie between their segment endpoints', () {
      const points = [PdfPoint(0, 0), PdfPoint(30, 0), PdfPoint(60, 0)];
      final first = fitCurve(points).first;

      expect(first.control1.x, inInclusiveRange(0, 30));
      expect(first.control2.x, inInclusiveRange(0, 30));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/stroke_smoothing_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/annotations/stroke_smoothing.dart`:
```dart
import 'dart:math' as math;

import 'package:folio/domain/annotations/pdf_point.dart';

/// One cubic Bézier segment. The start point is the previous segment's end, or
/// the path's initial `m` for the first segment.
class CubicSegment {
  const CubicSegment({
    required this.control1,
    required this.control2,
    required this.end,
  });

  final PdfPoint control1;
  final PdfPoint control2;
  final PdfPoint end;
}

/// Drops samples closer together than [minDistance].
///
/// A finger held still emits dozens of near-identical points; keeping them all
/// bloats /InkList and gains nothing visible. The final point is always kept,
/// because dropping it visibly shortens the stroke.
List<PdfPoint> thinSamples(List<PdfPoint> raw, {double minDistance = 2.0}) {
  if (raw.length < 2) return List.of(raw);

  final kept = <PdfPoint>[raw.first];
  for (final point in raw.skip(1)) {
    final last = kept.last;
    final dx = point.x - last.x;
    final dy = point.y - last.y;
    if (math.sqrt(dx * dx + dy * dy) >= minDistance) kept.add(point);
  }

  // Preserve the true end of the stroke even if it was too close to keep.
  if (kept.last != raw.last) kept.add(raw.last);
  return kept;
}

/// Fits a smooth curve through [points] as cubic Bézier segments.
///
/// Uses Catmull-Rom tangents converted to Bézier control points, which passes
/// exactly through every input point - important because those are the
/// positions the user actually touched.
List<CubicSegment> fitCurve(List<PdfPoint> points) {
  if (points.length < 2) return const [];

  final segments = <CubicSegment>[];
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = i == 0 ? points[i] : points[i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = i + 2 < points.length ? points[i + 2] : p2;

    // Catmull-Rom to Bézier: control points sit one sixth of the neighbouring
    // span away from each endpoint.
    segments.add(
      CubicSegment(
        control1: PdfPoint(
          p1.x + (p2.x - p0.x) / 6,
          p1.y + (p2.y - p0.y) / 6,
        ),
        control2: PdfPoint(
          p2.x - (p3.x - p1.x) / 6,
          p2.y - (p3.y - p1.y) / 6,
        ),
        end: p2,
      ),
    );
  }
  return segments;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/stroke_smoothing_test.dart`
Expected: PASS — 11 tests

- [ ] **Step 5: Mutation-test the endpoint guarantee**

In `thinSamples`, delete the `if (kept.last != raw.last) kept.add(raw.last);` line. Run the suite.

Expected: `the last point is always kept` FAILS. Revert and confirm green. Without it every stroke ends slightly short of where the user lifted their finger.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: add stroke thinning and Bezier fitting

Thinning drops samples a finger emits while barely moving, which would
otherwise bloat /InkList for no visible gain; the final point is always kept,
verified by mutation, because dropping it shortens every stroke.

Catmull-Rom tangents converted to Bezier control points pass exactly through
each input point, which matters because those are the positions the user
actually touched."
```

---

### Task 3: Sealed Annotation and DrawingAnnotation

**Files:**
- Create: `lib/domain/annotations/annotation.dart`, `lib/domain/annotations/drawing_annotation.dart`
- Modify: `lib/domain/annotations/text_markup.dart`
- Test: `test/domain/annotations/drawing_annotation_test.dart`

**Interfaces:**
- Consumes: `PdfPoint` (Task 1)
- Produces: `sealed class Annotation` with `int get pageIndex` and `String get pdfSubtype`; `enum DrawingKind { ink, rectangle, ellipse, line, arrow }`; `DrawingAnnotation({required DrawingKind kind, required int pageIndex, required List<PdfPoint> points, int colorArgb = 0xFF000000, double strokeWidth = 2})` with `String get pdfSubtype`, `({double left, double bottom, double right, double top}) get boundsPt`, `String get pdfColour`; `TextMarkup` now `final class TextMarkup extends Annotation`

**PDF's `/Circle` draws an ellipse inscribed in its `/Rect`, not a circle.** `DrawingKind.ellipse` maps to subtype `Circle`. Getting this backwards yields either a wrong subtype or a surprised user.

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/drawing_annotation_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/drawing_annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';

DrawingAnnotation drawing(DrawingKind kind, [List<PdfPoint>? points]) =>
    DrawingAnnotation(
      kind: kind,
      pageIndex: 0,
      points: points ?? const [PdfPoint(10, 20), PdfPoint(50, 80)],
    );

void main() {
  group('pdfSubtype', () {
    test('ink is /Ink', () {
      expect(drawing(DrawingKind.ink).pdfSubtype, 'Ink');
    });

    test('rectangle is /Square', () {
      expect(drawing(DrawingKind.rectangle).pdfSubtype, 'Square');
    });

    // PDF's /Circle draws an ellipse inscribed in /Rect. The enum says what it
    // draws; the subtype says what the format calls it.
    test('ellipse is /Circle, because that is what PDF calls an oval', () {
      expect(drawing(DrawingKind.ellipse).pdfSubtype, 'Circle');
    });

    test('line is /Line', () {
      expect(drawing(DrawingKind.line).pdfSubtype, 'Line');
    });

    test('arrow is also /Line, distinguished by its line ending', () {
      expect(drawing(DrawingKind.arrow).pdfSubtype, 'Line');
    });
  });

  group('boundsPt', () {
    test('spans every point', () {
      final b = drawing(DrawingKind.ink, const [
        PdfPoint(10, 90),
        PdfPoint(70, 20),
        PdfPoint(40, 55),
      ]).boundsPt;

      expect(b.left, 10);
      expect(b.right, 70);
      expect(b.bottom, 20);
      expect(b.top, 90);
    });

    // A drag up-and-left must give the same rectangle as down-and-right, or
    // shapes drawn in three of the four directions would be inside out.
    test('a reversed drag produces the same rectangle', () {
      final forward = drawing(DrawingKind.rectangle, const [
        PdfPoint(10, 20),
        PdfPoint(50, 80),
      ]).boundsPt;
      final reverse = drawing(DrawingKind.rectangle, const [
        PdfPoint(50, 80),
        PdfPoint(10, 20),
      ]).boundsPt;

      expect(reverse.left, forward.left);
      expect(reverse.right, forward.right);
      expect(reverse.bottom, forward.bottom);
      expect(reverse.top, forward.top);
    });

    test('a single point produces a degenerate rectangle, not a crash', () {
      final b = drawing(DrawingKind.ink, const [PdfPoint(10, 10)]).boundsPt;
      expect(b.left, 10);
      expect(b.right, 10);
    });
  });

  group('pdfColour', () {
    test('black is 0 0 0', () {
      expect(drawing(DrawingKind.ink).pdfColour, '0 0 0');
    });

    test('a red stroke converts to components in 0..1', () {
      const red = DrawingAnnotation(
        kind: DrawingKind.ink,
        pageIndex: 0,
        points: [PdfPoint(0, 0), PdfPoint(1, 1)],
        colorArgb: 0xFFFF0000,
      );
      expect(red.pdfColour, '1 0 0');
    });
  });

  group('the sealed hierarchy', () {
    test('both kinds are Annotations', () {
      expect(drawing(DrawingKind.ink), isA<Annotation>());
      expect(
        const TextMarkup(
          kind: MarkupKind.highlight,
          pageIndex: 0,
          quads: [TextRect(left: 0, top: 10, right: 10, bottom: 0)],
        ),
        isA<Annotation>(),
      );
    });

    test('a list can hold both', () {
      final list = <Annotation>[
        drawing(DrawingKind.ink),
        const TextMarkup(
          kind: MarkupKind.underline,
          pageIndex: 1,
          quads: [TextRect(left: 0, top: 10, right: 10, bottom: 0)],
        ),
      ];
      expect(list.map((a) => a.pageIndex), [0, 1]);
      expect(list.map((a) => a.pdfSubtype), ['Ink', 'Underline']);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/drawing_annotation_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Define the supertype**

`lib/domain/annotations/annotation.dart`:
```dart
/// Anything that can be staged and written into a PDF as an annotation object.
///
/// Sealed so the writer's switch over annotation kinds is exhaustive: adding a
/// kind without teaching the writer about it becomes a compile error.
sealed class Annotation {
  const Annotation();

  /// Zero-based page this annotation belongs to.
  int get pageIndex;

  /// The PDF annotation subtype name, without the leading slash.
  String get pdfSubtype;
}
```

- [ ] **Step 4: Make TextMarkup a variant**

In `lib/domain/annotations/text_markup.dart`, add the import and change the declaration. Everything else in the file is unchanged:
```dart
import 'package:folio/domain/annotations/annotation.dart';

// ...

final class TextMarkup extends Annotation {
  const TextMarkup({
    required this.kind,
    required this.pageIndex,
    required this.quads,
    this.colorArgb = 0xFFFFFF00,
  });

  final MarkupKind kind;

  @override
  final int pageIndex;

  // ... rest unchanged, with @override added to pdfSubtype
```

- [ ] **Step 5: Implement DrawingAnnotation**

`lib/domain/annotations/drawing_annotation.dart`:
```dart
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

enum DrawingKind { ink, rectangle, ellipse, line, arrow }

/// A freehand stroke or geometric shape staged for writing.
///
/// [points] are PDF user space, y-up. For [DrawingKind.ink] they are the
/// smoothed path; for shapes they are the two corners of the user's drag, in
/// whatever order it happened.
final class DrawingAnnotation extends Annotation {
  const DrawingAnnotation({
    required this.kind,
    required this.pageIndex,
    required this.points,
    this.colorArgb = 0xFF000000,
    this.strokeWidth = 2,
  });

  final DrawingKind kind;

  @override
  final int pageIndex;

  final List<PdfPoint> points;
  final int colorArgb;
  final double strokeWidth;

  /// PDF's /Circle draws an ellipse inscribed in its /Rect - it is not a
  /// circle. An arrow is a /Line distinguished by its line ending.
  @override
  String get pdfSubtype => switch (kind) {
    DrawingKind.ink => 'Ink',
    DrawingKind.rectangle => 'Square',
    DrawingKind.ellipse => 'Circle',
    DrawingKind.line || DrawingKind.arrow => 'Line',
  };

  /// The bounding box in PDF space. Normalised, so a drag in any direction
  /// gives the same rectangle.
  ({double left, double bottom, double right, double top}) get boundsPt {
    var left = points.first.x;
    var right = points.first.x;
    var bottom = points.first.y;
    var top = points.first.y;

    for (final p in points) {
      if (p.x < left) left = p.x;
      if (p.x > right) right = p.x;
      if (p.y < bottom) bottom = p.y;
      if (p.y > top) top = p.y;
    }
    return (left: left, bottom: bottom, right: right, top: top);
  }

  /// PDF colour components, each 0..1, space separated.
  String get pdfColour {
    String c(int shift) =>
        (((colorArgb >> shift) & 0xFF) / 255).toStringAsFixed(3);
    return '${c(16)} ${c(8)} ${c(0)}'.replaceAll(RegExp(r'\.000\b'), '');
  }
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/domain/annotations/drawing_annotation_test.dart`
Expected: PASS — 12 tests

- [ ] **Step 7: Verify SP-3a still passes**

Run: `flutter test`
Expected: all pass. `TextMarkup` gained a supertype; its behaviour is unchanged, and the SP-3a tests prove it.

- [ ] **Step 8: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: add sealed Annotation supertype and DrawingAnnotation

TextMarkup becomes a variant, unchanged in behaviour, so one session can hold
markup and drawings together.

DrawingKind.ellipse maps to PDF subtype Circle, because PDF's /Circle draws an
ellipse inscribed in its /Rect rather than a circle. Bounds are normalised so
a drag in any of the four directions gives the same rectangle."
```

---

### Task 4: Generalise AnnotationSession

**Files:**
- Modify: `lib/domain/annotations/annotation_session.dart`
- Test: `test/domain/annotations/annotation_session_test.dart`

**Interfaces:**
- Consumes: `Annotation` (Task 3)
- Produces: `AnnotationSession` now exposing `List<Annotation> get annotations`, `void add(Annotation)`, `List<Annotation> annotationsOnPage(int)`; `removeAt`, `undo`, `redo`, `isEmpty`, `isDirty`, `canUndo`, `canRedo` unchanged

- [ ] **Step 1: Extend the existing test file**

Append to `test/domain/annotations/annotation_session_test.dart`, keeping the SP-3a tests and renaming `markups` to `annotations` throughout:
```dart
  group('mixed annotation types', () {
    test('holds markup and drawings together', () {
      final s = AnnotationSession()
        ..add(markup())
        ..add(
          const DrawingAnnotation(
            kind: DrawingKind.ink,
            pageIndex: 0,
            points: [PdfPoint(0, 0), PdfPoint(10, 10)],
          ),
        );

      expect(s.annotations, hasLength(2));
      expect(s.annotations.map((a) => a.pdfSubtype), ['Highlight', 'Ink']);
    });

    // One undo stack across both kinds is the whole reason for generalising.
    test('undo crosses annotation types', () {
      final s = AnnotationSession()
        ..add(markup())
        ..add(
          const DrawingAnnotation(
            kind: DrawingKind.rectangle,
            pageIndex: 0,
            points: [PdfPoint(0, 0), PdfPoint(10, 10)],
          ),
        );

      s.undo();
      expect(s.annotations, hasLength(1));
      expect(s.annotations.single, isA<TextMarkup>());

      s.undo();
      expect(s.annotations, isEmpty);
    });

    test('annotationsOnPage filters both kinds', () {
      final s = AnnotationSession()
        ..add(markup(page: 0))
        ..add(
          const DrawingAnnotation(
            kind: DrawingKind.ink,
            pageIndex: 0,
            points: [PdfPoint(0, 0), PdfPoint(1, 1)],
          ),
        )
        ..add(markup(page: 3));

      expect(s.annotationsOnPage(0), hasLength(2));
      expect(s.annotationsOnPage(3), hasLength(1));
    });
  });
```

Add the imports for `annotation.dart`, `drawing_annotation.dart` and `pdf_point.dart`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/annotation_session_test.dart`
Expected: FAIL — `annotations` is not defined, `add` will not accept a `DrawingAnnotation`

- [ ] **Step 3: Generalise the session**

In `lib/domain/annotations/annotation_session.dart`, replace every `TextMarkup` with `Annotation`, import `annotation.dart`, and rename the accessors:
```dart
import 'package:folio/domain/annotations/annotation.dart';

/// Annotations staged for writing.
///
/// Holds text markup and drawings together, so one undo stack and one Save
/// serve both. Nothing touches a PDF until the caller saves.
class AnnotationSession {
  List<Annotation> _annotations = [];
  final List<List<Annotation>> _undo = [];
  final List<List<Annotation>> _redo = [];

  List<Annotation> get annotations => List.unmodifiable(_annotations);

  bool get isEmpty => _annotations.isEmpty;
  bool get isDirty => _annotations.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  List<Annotation> annotationsOnPage(int pageIndex) =>
      _annotations.where((a) => a.pageIndex == pageIndex).toList();

  void _mutate(void Function(List<Annotation>) change) {
    final snapshot = List.of(_annotations);
    final working = List.of(_annotations);
    change(working);
    _undo.add(snapshot);
    _redo.clear();
    _annotations = working;
  }

  void add(Annotation annotation) =>
      _mutate((list) => list.add(annotation));

  void removeAt(int index) {
    RangeError.checkValidIndex(index, _annotations, 'index');
    _mutate((list) => list.removeAt(index));
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(List.of(_annotations));
    _annotations = _undo.removeLast();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(List.of(_annotations));
    _annotations = _redo.removeLast();
  }
}
```

- [ ] **Step 4: Update every caller**

The analyzer will name them. Expect: `annotation_providers.dart` (`session.markups` → `session.annotations`), `annotation_repository_impl.dart` and `pdf_annotation_writer.dart` (parameter types `List<TextMarkup>` → `List<Annotation>`), `markup_toolbar.dart`.

For now, `writeMarkup` may narrow with a runtime filter so this task compiles; Task 6 makes it handle drawings properly:
```dart
  final markups = annotations.whereType<TextMarkup>().toList();
```

- [ ] **Step 5: Run to verify it passes**

Run: `dart format lib test && flutter analyze --fatal-infos && flutter test`
Expected: analyzer clean; all tests pass, including every SP-3a test.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: generalise AnnotationSession over sealed Annotation

One session, one undo stack and one Save for markup and drawings together.
Parallel sessions would have given a user two undo stacks and produced two
documents from a single editing session."
```

---

# Stage 2 — The write path

Ends with: drawings written into a real PDF and verified by rendering them back.

---

### Task 5: Drawing appearance streams

**Files:**
- Create: `lib/domain/annotations/drawing_appearance.dart`
- Test: `test/domain/annotations/drawing_appearance_test.dart`

**Interfaces:**
- Consumes: `DrawingAnnotation`, `DrawingKind` (Task 3), `fitCurve`/`CubicSegment` (Task 2), `pdfNumber` from `pdf_appearance.dart`
- Produces: `String drawingAppearanceStream(DrawingAnnotation)`; `String drawingAppearanceDict(DrawingAnnotation, int streamLength)`

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/drawing_appearance_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/drawing_annotation.dart';
import 'package:folio/domain/annotations/drawing_appearance.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

DrawingAnnotation of(DrawingKind kind, [List<PdfPoint>? pts]) =>
    DrawingAnnotation(
      kind: kind,
      pageIndex: 0,
      points: pts ?? const [PdfPoint(10, 20), PdfPoint(50, 80)],
      strokeWidth: 3,
    );

void main() {
  group('stroke settings', () {
    test('the stroke width is emitted', () {
      expect(drawingAppearanceStream(of(DrawingKind.line)), contains('3 w'));
    });

    test('the colour is emitted as a stroking colour', () {
      expect(drawingAppearanceStream(of(DrawingKind.line)), contains('0 0 0 RG'));
    });

    // Round caps and joins are what make a freehand stroke look like ink
    // rather than a chain of segments.
    test('ink uses round caps and joins', () {
      final s = drawingAppearanceStream(
        of(DrawingKind.ink, const [
          PdfPoint(0, 0),
          PdfPoint(10, 10),
          PdfPoint(20, 0),
        ]),
      );
      expect(s, contains('1 J'));
      expect(s, contains('1 j'));
    });
  });

  group('ink', () {
    test('moves to the first point then emits curves', () {
      final s = drawingAppearanceStream(
        of(DrawingKind.ink, const [
          PdfPoint(0, 0),
          PdfPoint(10, 10),
          PdfPoint(20, 0),
        ]),
      );

      expect(s, contains('0 0 m'));
      expect(s, contains('c'));
      expect(s, contains('S'));
    });

    test('a two-point stroke still produces a path', () {
      final s = drawingAppearanceStream(
        of(DrawingKind.ink, const [PdfPoint(0, 0), PdfPoint(10, 0)]),
      );
      expect(s, contains('m'));
      expect(s, contains('S'));
    });

    test('a single-point stroke produces no path rather than crashing', () {
      final s = drawingAppearanceStream(
        of(DrawingKind.ink, const [PdfPoint(5, 5)]),
      );
      expect(s, isNot(contains('c')));
    });
  });

  group('shapes', () {
    test('rectangle emits a stroked re', () {
      final s = drawingAppearanceStream(of(DrawingKind.rectangle));
      expect(s, contains('re'));
      expect(s, contains('S'));
      expect(s, contains('10 20 40 60 re'), reason: 'x y width height');
    });

    // PDF has no ellipse operator; four Bezier arcs approximate one.
    test('ellipse emits four curves, not a rectangle', () {
      final s = drawingAppearanceStream(of(DrawingKind.ellipse));
      expect('c'.allMatches(s).length, greaterThanOrEqualTo(4));
      expect(s, isNot(contains(' re')));
    });

    test('line emits a move and a lineto', () {
      final s = drawingAppearanceStream(of(DrawingKind.line));
      expect(s, contains('10 20 m'));
      expect(s, contains('50 80 l'));
    });

    // An arrow is a line plus a head; without the extra strokes it is just a
    // line and the tool would appear broken.
    test('arrow emits more path segments than a plain line', () {
      final line = 'l'.allMatches(drawingAppearanceStream(of(DrawingKind.line))).length;
      final arrow = 'l'.allMatches(drawingAppearanceStream(of(DrawingKind.arrow))).length;
      expect(arrow, greaterThan(line));
    });
  });

  group('drawingAppearanceDict', () {
    test('is a form XObject whose BBox covers the drawing plus stroke width', () {
      final d = drawingAppearanceDict(of(DrawingKind.rectangle), 42);

      expect(d, contains('/Type /XObject'));
      expect(d, contains('/Subtype /Form'));
      expect(d, contains('/Length 42'));
      // Bounds 10,20..50,80 grown by half the 3pt stroke, rounded outward.
      expect(d, contains('/BBox [8.5 18.5 51.5 81.5]'));
    });

    test('a zero-area drawing still gets a non-degenerate BBox', () {
      final d = drawingAppearanceDict(
        of(DrawingKind.ink, const [PdfPoint(10, 10), PdfPoint(10, 10)]),
        10,
      );
      expect(d, contains('/BBox'));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/drawing_appearance_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/annotations/drawing_appearance.dart`:
```dart
import 'dart:math' as math;

import 'package:folio/domain/annotations/drawing_annotation.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart' show pdfNumber;
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/stroke_smoothing.dart';

/// Magic constant for approximating a quarter ellipse with a cubic Bezier.
/// PDF has no ellipse operator, so four of these make an oval.
const double _kappa = 0.5523;

/// Content stream drawing this annotation's appearance.
String drawingAppearanceStream(DrawingAnnotation drawing) {
  final b = drawing.boundsPt;
  final buffer = StringBuffer()
    ..writeln('${drawing.pdfColour} RG')
    ..writeln('${pdfNumber(drawing.strokeWidth)} w')
    // Round caps and joins: without them a freehand stroke reads as a chain of
    // straight segments with visible corners.
    ..writeln('1 J')
    ..writeln('1 j');

  switch (drawing.kind) {
    case DrawingKind.ink:
      if (drawing.points.length < 2) return buffer.toString();
      final first = drawing.points.first;
      buffer.writeln('${pdfNumber(first.x)} ${pdfNumber(first.y)} m');
      for (final s in fitCurve(drawing.points)) {
        buffer.writeln(
          '${pdfNumber(s.control1.x)} ${pdfNumber(s.control1.y)} '
          '${pdfNumber(s.control2.x)} ${pdfNumber(s.control2.y)} '
          '${pdfNumber(s.end.x)} ${pdfNumber(s.end.y)} c',
        );
      }
      buffer.writeln('S');

    case DrawingKind.rectangle:
      buffer.writeln(
        '${pdfNumber(b.left)} ${pdfNumber(b.bottom)} '
        '${pdfNumber(b.right - b.left)} ${pdfNumber(b.top - b.bottom)} re',
      );
      buffer.writeln('S');

    case DrawingKind.ellipse:
      _writeEllipse(buffer, b);
      buffer.writeln('S');

    case DrawingKind.line:
      final a = drawing.points.first;
      final z = drawing.points.last;
      buffer.writeln('${pdfNumber(a.x)} ${pdfNumber(a.y)} m');
      buffer.writeln('${pdfNumber(z.x)} ${pdfNumber(z.y)} l');
      buffer.writeln('S');

    case DrawingKind.arrow:
      final a = drawing.points.first;
      final z = drawing.points.last;
      buffer.writeln('${pdfNumber(a.x)} ${pdfNumber(a.y)} m');
      buffer.writeln('${pdfNumber(z.x)} ${pdfNumber(z.y)} l');
      _writeArrowHead(buffer, a, z, drawing.strokeWidth);
      buffer.writeln('S');
  }

  return buffer.toString();
}

void _writeEllipse(
  StringBuffer buffer,
  ({double left, double bottom, double right, double top}) b,
) {
  final cx = (b.left + b.right) / 2;
  final cy = (b.bottom + b.top) / 2;
  final rx = (b.right - b.left) / 2;
  final ry = (b.top - b.bottom) / 2;
  final ox = rx * _kappa;
  final oy = ry * _kappa;

  String n(double v) => pdfNumber(v);

  buffer.writeln('${n(cx - rx)} ${n(cy)} m');
  buffer.writeln('${n(cx - rx)} ${n(cy + oy)} ${n(cx - ox)} ${n(cy + ry)} ${n(cx)} ${n(cy + ry)} c');
  buffer.writeln('${n(cx + ox)} ${n(cy + ry)} ${n(cx + rx)} ${n(cy + oy)} ${n(cx + rx)} ${n(cy)} c');
  buffer.writeln('${n(cx + rx)} ${n(cy - oy)} ${n(cx + ox)} ${n(cy - ry)} ${n(cx)} ${n(cy - ry)} c');
  buffer.writeln('${n(cx - ox)} ${n(cy - ry)} ${n(cx - rx)} ${n(cy - oy)} ${n(cx - rx)} ${n(cy)} c');
}

/// Two short strokes back from the tip, forming a V.
void _writeArrowHead(
  StringBuffer buffer,
  PdfPoint from,
  PdfPoint to,
  double strokeWidth,
) {
  final angle = math.atan2(to.y - from.y, to.x - from.x);
  final length = math.max(8.0, strokeWidth * 4);
  const spread = 0.5; // radians either side of the shaft

  for (final side in [angle + math.pi - spread, angle + math.pi + spread]) {
    buffer.writeln('${pdfNumber(to.x)} ${pdfNumber(to.y)} m');
    buffer.writeln(
      '${pdfNumber(to.x + length * math.cos(side))} '
      '${pdfNumber(to.y + length * math.sin(side))} l',
    );
  }
}

/// The form XObject dictionary wrapping [drawingAppearanceStream].
String drawingAppearanceDict(DrawingAnnotation drawing, int streamLength) {
  final b = drawing.boundsPt;
  // Grow by half the stroke width: a stroke straddles its path, so a tight
  // BBox would clip the outer half of every edge.
  final pad = drawing.strokeWidth / 2;
  final bbox =
      '[${pdfNumber(b.left - pad)} ${pdfNumber(b.bottom - pad)} '
      '${pdfNumber(b.right + pad)} ${pdfNumber(b.top + pad)}]';

  return '<< /Type /XObject /Subtype /Form /BBox $bbox '
      '/Resources << >> /Length $streamLength >>';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/drawing_appearance_test.dart`
Expected: PASS — 12 tests

- [ ] **Step 5: Mutation-test the BBox padding**

In `drawingAppearanceDict`, change `final pad = drawing.strokeWidth / 2;` to `final pad = 0.0;`. Run the suite.

Expected: `is a form XObject whose BBox covers the drawing plus stroke width` FAILS. Revert. Without padding, the outer half of every stroke is clipped by its own bounding box — subtle enough to miss in review, obvious on screen.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: add appearance streams for ink and shapes

Ink emits Bezier curves through the smoothed path with round caps and joins,
without which a stroke reads as a chain of straight segments. PDF has no
ellipse operator, so an oval is four Bezier arcs.

The BBox grows by half the stroke width, verified by mutation: a stroke
straddles its path, so a tight box clips the outer half of every edge."
```

---

### Task 6: Teach the writer about drawings

**Files:**
- Modify: `lib/domain/annotations/pdf_annotation_writer.dart`
- Test: `test/domain/annotations/pdf_annotation_writer_test.dart`

**Interfaces:**
- Consumes: `Annotation` (Task 3), `drawingAppearanceStream`/`drawingAppearanceDict` (Task 5)
- Produces: `Uint8List writeAnnotations(Uint8List pdf, List<Annotation> annotations)` — renamed from `writeMarkup`, with the Task 4 runtime filter removed; and `AnnotationRepository.saveAnnotations({required int sourceDocumentId, required List<Annotation> annotations})` — widened and renamed from `saveMarkup`

- [ ] **Step 1: Add the failing tests**

Append to `test/domain/annotations/pdf_annotation_writer_test.dart`:
```dart
  group('drawings', () {
    DrawingAnnotation ink() => const DrawingAnnotation(
      kind: DrawingKind.ink,
      pageIndex: 0,
      points: [PdfPoint(60, 700), PdfPoint(90, 730), PdfPoint(120, 700)],
    );

    test('emits an /Ink annotation with an /InkList', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [ink()]));

      expect(text, contains('/Subtype /Ink'));
      expect(text, contains('/InkList'));
      // Alternating x y, one array per stroke.
      expect(text, contains('[[60 700 90 730 120 700]]'));
    });

    test('emits /Square with a /Rect for a rectangle', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          const DrawingAnnotation(
            kind: DrawingKind.rectangle,
            pageIndex: 0,
            points: [PdfPoint(60, 700), PdfPoint(160, 760)],
          ),
        ]),
      );

      expect(text, contains('/Subtype /Square'));
      expect(text, contains('/Rect [60 700 160 760]'));
    });

    test('emits /Circle for an oval', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          const DrawingAnnotation(
            kind: DrawingKind.ellipse,
            pageIndex: 0,
            points: [PdfPoint(60, 700), PdfPoint(160, 760)],
          ),
        ]),
      );
      expect(text, contains('/Subtype /Circle'));
    });

    test('emits /Line with an /L array', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          const DrawingAnnotation(
            kind: DrawingKind.line,
            pageIndex: 0,
            points: [PdfPoint(60, 700), PdfPoint(160, 760)],
          ),
        ]),
      );

      expect(text, contains('/Subtype /Line'));
      expect(text, contains('/L [60 700 160 760]'));
    });

    test('an arrow declares a line ending so viewers draw the head', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          const DrawingAnnotation(
            kind: DrawingKind.arrow,
            pageIndex: 0,
            points: [PdfPoint(60, 700), PdfPoint(160, 760)],
          ),
        ]),
      );
      expect(text, contains('/LE'));
    });

    test('every drawing gets an appearance stream', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [ink()]));
      expect(text, contains('/AP'));
      expect(text, contains('/Subtype /Form'));
    });

    // The point of the sealed type: one save, both kinds.
    test('markup and drawings write together in one pass', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [markup(), ink()]),
      );

      expect(text, contains('/Subtype /Highlight'));
      expect(text, contains('/Subtype /Ink'));
      // Still exactly one page override.
      expect(RegExp(r'3 0 obj').allMatches(text).length, 2);
    });
  });
```

Add imports for `drawing_annotation.dart` and `pdf_point.dart`, and rename existing `writeMarkup(` calls to `writeAnnotations(`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_annotation_writer_test.dart`
Expected: FAIL — `writeAnnotations` is not defined

- [ ] **Step 3: Implement**

In `lib/domain/annotations/pdf_annotation_writer.dart`, rename the function, drop the `whereType<TextMarkup>()` filter from Task 4, and switch on the sealed type when emitting:
```dart
Uint8List writeAnnotations(Uint8List pdf, List<Annotation> annotations) {
```

Replace the per-annotation emission block with:
```dart
    for (final annotation in entry.value) {
      final (stream, dict) = switch (annotation) {
        TextMarkup() => (
          appearanceStream(annotation),
          appearanceDict(annotation, appearanceStream(annotation).length),
        ),
        DrawingAnnotation() => (
          drawingAppearanceStream(annotation),
          drawingAppearanceDict(
            annotation,
            drawingAppearanceStream(annotation).length,
          ),
        ),
      };

      final apNum = nextObj++;
      emit(apNum, '$dict\nstream\n${stream}endstream');

      final annotNum = nextObj++;
      emit(annotNum, _annotationDict(annotation, apNum));
      newRefs.add('$annotNum 0 R');
    }
```

And add the geometry emitter:
```dart
/// The annotation dictionary. Geometry differs per subtype: markup uses
/// /QuadPoints, ink uses /InkList, a line uses /L, and shapes use /Rect alone.
String _annotationDict(Annotation annotation, int apNum) {
  final ap = '/AP << /N $apNum 0 R >>';

  switch (annotation) {
    case TextMarkup():
      final b = annotation.boundingRect;
      return '<< /Type /Annot /Subtype /${annotation.pdfSubtype} '
          '/Rect [${pdfNumber(b.left)} ${pdfNumber(b.bottom)} '
          '${pdfNumber(b.right)} ${pdfNumber(b.top)}] '
          '/QuadPoints [${annotation.quadPoints.map(pdfNumber).join(' ')}] '
          '/C [${annotation.pdfColour}] /CA 1 /F 4 $ap >>';

    case DrawingAnnotation():
      final b = annotation.boundsPt;
      final rect =
          '/Rect [${pdfNumber(b.left)} ${pdfNumber(b.bottom)} '
          '${pdfNumber(b.right)} ${pdfNumber(b.top)}]';
      final common =
          '/Type /Annot /Subtype /${annotation.pdfSubtype} $rect '
          '/C [${annotation.pdfColour}] /CA 1 /F 4 '
          '/BS << /W ${pdfNumber(annotation.strokeWidth)} >>';

      final geometry = switch (annotation.kind) {
        DrawingKind.ink =>
          ' /InkList [[${annotation.points.map((p) => '${pdfNumber(p.x)} ${pdfNumber(p.y)}').join(' ')}]]',
        DrawingKind.line =>
          ' /L [${pdfNumber(annotation.points.first.x)} '
              '${pdfNumber(annotation.points.first.y)} '
              '${pdfNumber(annotation.points.last.x)} '
              '${pdfNumber(annotation.points.last.y)}]',
        // /OpenArrow at the end of the shaft; viewers that honour /LE draw the
        // head themselves, and our /AP draws it for those that do not.
        DrawingKind.arrow =>
          ' /L [${pdfNumber(annotation.points.first.x)} '
              '${pdfNumber(annotation.points.first.y)} '
              '${pdfNumber(annotation.points.last.x)} '
              '${pdfNumber(annotation.points.last.y)}]'
              ' /LE [/None /OpenArrow]',
        DrawingKind.rectangle || DrawingKind.ellipse => '',
      };

      return '<< $common$geometry $ap >>';
  }
}
```

- [ ] **Step 3b: Widen the repository to accept any annotation**

The repository still takes `List<TextMarkup>`, so drawings could not reach it.
Widen and rename it, in `lib/domain/repositories/annotation_repository.dart`:
```dart
abstract interface class AnnotationRepository {
  Future<LibraryDocument> saveAnnotations({
    required int sourceDocumentId,
    required List<Annotation> annotations,
  });
}
```

and in `lib/data/repositories/annotation_repository_impl.dart` rename the
parameter, call `writeAnnotations(bytes, annotations)`, and keep the
empty-list guard:
```dart
    if (annotations.isEmpty) {
      throw ArgumentError.value(annotations, 'annotations', 'nothing to save');
    }
```

Update `test/data/repositories/annotation_repository_test.dart` to the new name
and type. Its assertions are unchanged — the source stays byte-identical and
metadata still survives.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_annotation_writer_test.dart`
Expected: PASS — all SP-3a tests plus 7 new

- [ ] **Step 5: Full suite and analyze**

Run: `dart format lib test && flutter analyze --fatal-infos && flutter test`
Expected: analyzer clean; everything passes.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: write ink and shape annotations

Renames writeMarkup to writeAnnotations and switches on the sealed Annotation
type, so adding a kind without teaching the writer becomes a compile error.

Geometry differs per subtype: markup uses /QuadPoints, ink /InkList, lines /L,
and shapes rely on /Rect. Arrows declare /LE OpenArrow for viewers that honour
it, while the appearance stream draws the head for those that do not."
```

---

# Stage 3 — Drawing surface and verification

---

### Task 7: Drawing surface

**Files:**
- Create: `lib/features/viewer/widgets/drawing_surface.dart`
- Modify: `lib/features/viewer/annotation_providers.dart`
- Test: `test/features/viewer/drawing_controller_test.dart`

**Interfaces:**
- Consumes: `canvasToPdf` (Task 1), `thinSamples` (Task 2), `DrawingAnnotation` (Task 3)
- Produces: `DrawingSurface({required DrawingKind tool, required int colorArgb, required double strokeWidth, required Rect Function(int pageIndex) pageRectFor, required PdfPage Function(int) pageFor, required int currentPageIndex})`; controller gains `void beginStroke(Offset)`, `void extendStroke(Offset)`, `void endStroke()`, `List<Offset> get liveStroke`

- [ ] **Step 1: Write the failing controller test**

`test/features/viewer/drawing_controller_test.dart`:
```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/drawing_annotation.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

const pageRect = Rect.fromLTWH(0, 0, 595, 842);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationController c() => container.read(annotationSessionProvider.notifier);
  AnnotationState s() => container.read(annotationSessionProvider);

  test('a stroke in progress is visible before it is committed', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..extendStroke(const Offset(40, 40));

    expect(s().liveStroke, hasLength(2));
    expect(s().session.annotations, isEmpty, reason: 'not committed yet');
  });

  test('ending a stroke commits it and clears the live points', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..extendStroke(const Offset(40, 40))
      ..endStroke(
        tool: DrawingKind.ink,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

    expect(s().liveStroke, isEmpty);
    expect(s().session.annotations, hasLength(1));
  });

  // A tap with no drag must not leave an invisible dot annotation behind.
  test('a stroke of one point commits nothing', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..endStroke(
        tool: DrawingKind.ink,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

    expect(s().session.annotations, isEmpty);
  });

  test('a shape keeps only its first and last point', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..extendStroke(const Offset(25, 25))
      ..extendStroke(const Offset(40, 40))
      ..endStroke(
        tool: DrawingKind.rectangle,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

    final drawing = s().session.annotations.single as DrawingAnnotation;
    expect(drawing.points, hasLength(2));
  });

  test('committed points are in PDF space, not canvas space', () {
    c()
      ..beginStroke(const Offset(100, 10))
      ..extendStroke(const Offset(200, 20))
      ..endStroke(
        tool: DrawingKind.line,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

    final drawing = s().session.annotations.single as DrawingAnnotation;
    // Canvas y=10 is near the top, so PDF y must be large.
    expect(drawing.points.first.y, greaterThan(800));
  });

  test('undo removes a committed stroke', () {
    c()
      ..beginStroke(const Offset(10, 10))
      ..extendStroke(const Offset(40, 40))
      ..endStroke(
        tool: DrawingKind.ink,
        pageIndex: 0,
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );
    c().undo();

    expect(s().session.annotations, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/viewer/drawing_controller_test.dart`
Expected: FAIL — `beginStroke` is not defined

- [ ] **Step 3: Extend the controller**

In `lib/features/viewer/annotation_providers.dart`, add live-stroke state to `AnnotationState` and these methods to `AnnotationController`:
```dart
  /// Canvas-space points of the stroke currently under the finger. Kept in
  /// canvas space so the preview can be painted without converting back.
  void beginStroke(Offset point) {
    state = state.copyWith(liveStroke: [point]);
  }

  void extendStroke(Offset point) {
    state = state.copyWith(liveStroke: [...state.liveStroke, point]);
  }

  /// Commits the live stroke as an annotation in PDF space.
  ///
  /// Shapes keep only the first and last point - the drag's two corners - while
  /// ink keeps the thinned path.
  void endStroke({
    required DrawingKind tool,
    required int pageIndex,
    required Rect pageRect,
    required double pageWidthPt,
    required double pageHeightPt,
    int colorArgb = 0xFF000000,
    double strokeWidth = 2,
  }) {
    final live = state.liveStroke;
    // A tap with no drag would otherwise leave an invisible dot behind.
    if (live.length < 2) {
      state = state.copyWith(liveStroke: const []);
      return;
    }

    final canvasPoints = tool == DrawingKind.ink
        ? live
        : [live.first, live.last];

    final pdfPoints = [
      for (final p in canvasPoints)
        canvasToPdf(
          p,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
    ];

    state.session.add(
      DrawingAnnotation(
        kind: tool,
        pageIndex: pageIndex,
        points: tool == DrawingKind.ink ? thinSamples(pdfPoints) : pdfPoints,
        colorArgb: colorArgb,
        strokeWidth: strokeWidth,
      ),
    );
    state = state.copyWith(liveStroke: const []);
  }
```

`AnnotationState` gains `final List<Offset> liveStroke;`, defaulting to `const []`, and `copyWith` accepts it.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/viewer/drawing_controller_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 5: Build the surface**

`lib/features/viewer/widgets/drawing_surface.dart` is a `GestureDetector` wrapping a `CustomPaint` that:

- on `onPanStart`/`onPanUpdate`/`onPanEnd` calls `beginStroke`/`extendStroke`/`endStroke`
- paints `liveStroke` as a polyline in the current colour and width
- paints already-staged drawings for the current page by converting their PDF points back with `pdfToCanvas`, so staged work stays visible before saving
- is placed **above** the `PdfViewer` only in drawing mode, so it does not intercept scroll or pinch in read mode

Preview and output both derive from the same points, so what the user sees matches what is written.

- [ ] **Step 6: Verify on the simulator**

```bash
flutter run -d DFC5606D-37F0-4176-A73D-B8214C7F820F --dart-define-from-file=config/development.json
```

Draw a stroke, a rectangle, an oval, a line and an arrow. Undo. Zoom in and draw again — the stroke must land under the finger at any zoom. **Demo this on the simulator.**

- [ ] **Step 7: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add drawing surface with live preview

Strokes are captured in canvas space, previewed there, and converted to PDF
space only on commit, so the preview and the written path derive from the same
points. Shapes keep the drag's two corners; ink keeps the thinned path. A tap
with no drag commits nothing rather than leaving an invisible dot."
```

---

### Task 8: Drawing toolbar and mode

**Files:**
- Create: `lib/features/viewer/widgets/drawing_toolbar.dart`
- Modify: `lib/features/viewer/viewer_screen.dart`, `lib/l10n/app_en.arb`

- [ ] **Step 1: Add the strings**

```json
{
  "drawMode": "Draw",
  "drawPen": "Pen",
  "drawRectangle": "Rectangle",
  "drawOval": "Oval",
  "drawLine": "Line",
  "drawArrow": "Arrow",
  "drawColour": "Colour",
  "drawThickness": "Thickness",
  "drawUndo": "Undo",
  "drawSave": "Save with drawings",
  "drawDiscardPrompt": "Discard your drawings? The original document is untouched either way."
}
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Build the toolbar**

`drawing_toolbar.dart` presents the five tools as a segmented selection, a small colour row (black, red, blue, green, yellow), a thickness slider from 1 to 8, undo, and a **Save with drawings** action.

Keep Save in the always-visible row, never inside a horizontally scrolling one — that was a real defect in SP-2a and the reason SP-3a pins it.

- [ ] **Step 3: Add the mode to the viewer**

Extend `_ViewerMode` with `draw`. In draw mode the body stacks `DrawingSurface` over the `PdfViewer`, the toolbar replaces the page indicator, and leaving with a dirty session prompts with `l10n.drawDiscardPrompt`.

Saving calls `AnnotationRepository.saveMarkup` — which already accepts `List<Annotation>` after Task 6 — so markup and drawings staged together produce one document.

- [ ] **Step 4: Verify each tool on the simulator**

Draw with each of the five tools, change colour and thickness, undo, then save. Confirm a new document appears and the original opens unmarked. **Demo this on the simulator.**

- [ ] **Step 5: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add drawing toolbar and draw mode

Five tools, colour and thickness, sharing the annotation session with text
markup so both save together into one document."
```

---

### Task 9: End-to-end verification and documentation

**Files:**
- Create: `integration_test/drawing_flow_test.dart`
- Modify: `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`

- [ ] **Step 1: Write the end-to-end flows**

`integration_test/drawing_flow_test.dart` builds a real library, saves drawings through `AnnotationRepositoryImpl.saveAnnotations`, then reopens
and asserts:

1. an ink stroke **renders** — render before and after, require the pixels to differ
2. each of rectangle, oval, line and arrow renders
3. **drawing on `scanned_no_text.pdf` renders** — the case impossible before this slice, and the strongest evidence it was worth building
4. the source document's SHA-256 is unchanged
5. extracted text is unchanged
6. a highlight and a drawing saved together produce one document containing both `/Highlight` and `/Ink`
7. metadata survives, so SP-2b has not regressed
8. a cross-reference-stream document is refused with `UnsupportedPdfStructure`

- [ ] **Step 2: Run on the iOS simulator**

```bash
dart run scripts/make_fixtures.dart
flutter test integration_test -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including every SP-1, SP-2 and SP-3a suite.

- [ ] **Step 3: Run on the Android emulator**

```bash
flutter emulators --launch pixel_api35
flutter test integration_test -d emulator-5554
```

Expected: all pass. No Android claim before this.

- [ ] **Step 4: Verify PdfEngine is still write-free**

```bash
grep -nE "^\s+Future<.*> (write|save|export|materialise)" lib/domain/engine/pdf_engine.dart
```

Expected: no matches.

- [ ] **Step 5: Update the documentation**

- `FEATURES.md` — add the five drawing tools, ✅ where verified, 🟡 for Windows. Note that drawing works on scanned pages.
- `LIMITATIONS.md` — saved drawings cannot be edited or deleted, same as saved markup; fold this into the existing item 3 rather than adding a near-duplicate.
- `ARCHITECTURE.md` — the coordinate mapping and why it is a tested pure function.
- `TESTING.md` — refresh counts and the date.

- [ ] **Step 6: Full verification and push**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
git add -A && git commit -m "test: add end-to-end drawing flows and update docs

Every flow reopens the output and requires the drawing to render, including
on a scanned page with no text layer - the case that was impossible before
this slice. Source documents asserted byte-identical, metadata asserted to
survive."
git push origin feature/sp3b-ink-and-shapes
```

Confirm all four CI jobs pass, including `build-windows`.

---

## Definition of done

- [ ] Pen, rectangle, oval, line and arrow create, undo and save
- [ ] Saved drawings **render** on reopen, verified by pixel comparison
- [ ] Drawing works on a scanned page with no text layer
- [ ] Source documents byte-identical after every save
- [ ] Text markup and drawings share one session, undo stack and Save
- [ ] `PdfEngine` still has no write method
- [ ] `lib/domain/annotations` unit coverage ≥90%
- [ ] Integration passes on iOS simulator **and** Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] CI green on all four jobs including `build-windows`
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md`, `TESTING.md` updated

Report status in the brief's format:

```
PHASE STATUS
------------
Implemented:
Tests:
Platforms Verified:
Known Issues:
Dependencies Added:
License:
Next Phase:
```

**Next:** SP-3c — sticky notes and stamps — and separately, editing or deleting saved annotations, which needs reading `/Annots` back and should be scoped on its own evidence.
