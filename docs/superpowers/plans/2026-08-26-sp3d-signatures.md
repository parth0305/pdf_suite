# SP-3d — Signatures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw a signature once, save it with a label, and place it on any document by dragging a box.

**Architecture:** Ink geometry becomes a list of strokes rather than one polyline, matching what PDF's `/InkList` has always meant, so a signature is one annotation instead of several. Signatures are stored as strokes normalised into a unit box, y-up, and placed by fitting them into a dragged box with the aspect ratio preserved. Placement reuses `AnnotationRepository.saveAnnotations` unchanged — this slice adds nothing to the write path.

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5, pdfrx 2.4.7 (PDFium), drift 2.34.3, flutter_riverpod 3.3.2.

**Spec:** `docs/superpowers/specs/2026-08-26-sp3d-signatures-design.md`

## Global Constraints

- **Zero AI, zero paid or proprietary SDKs, no GPL/LGPL/AGPL.** No new dependencies in this slice.
- **Never destroy originals.** Placement goes through `saveAnnotations`, which already writes a new document.
- **`PdfEngine` has no write method and must not gain one.**
- **`PdfObjectReader` handles page dictionaries and nothing else.**
- **Never log document content, passwords, filenames or paths.** A signature is personal data: never log its strokes either.
- **Folio stamps no `/Producer`, no `/ModDate`, and no ownership marker.**
- **A feature is not done until it has been verified by rendering.**
- Run `dart format lib test integration_test scripts` and `flutter analyze --fatal-infos` before every commit.

## Critical context the implementer will not guess

**`points` survives as a getter.** There are 18 uses of `DrawingAnnotation.points` across the codebase. Keeping `points => strokes.first` means only four ink-specific sites change: `boundsPt`, the appearance generator's ink case, the writer's `/InkList`, and the preview painter. Do not chase the other fourteen.

**`boundsPt` is load-bearing and currently wrong for multi-stroke.** It iterates `points`. With several strokes it would bound only the first, producing a `/Rect` that is too small and a `/BBox` that clips most of the signature away. It must iterate every stroke.

**The reader flattens `/InkList` today.** `_numbersIn(dict, 'InkList')` returns every number in the nested array as one flat list, so `[[10 10 20 20] [80 80 90 90]]` reads back as a single four-point path. Restyling such an annotation regenerates its appearance with a line drawn through the gap. This is a live SP-3c defect, probed on 2026-08-26, and Task 1 fixes it.

**Normalised means unit box, y-up.** PDF user space is y-up, so storing signatures y-up makes placement a multiply and an offset with no flip. A flip bug here puts every signature upside down.

## File structure

| File | Responsibility |
|---|---|
| `lib/domain/annotations/drawing_annotation.dart` | **Modify.** `strokes` is the stored geometry; `points` becomes `strokes.first`; `boundsPt` spans every stroke. |
| `lib/domain/annotations/drawing_appearance.dart` | **Modify.** One subpath per stroke. |
| `lib/domain/annotations/pdf_annotation_writer.dart` | **Modify.** `/InkList` emits one array per stroke. |
| `lib/domain/annotations/pdf_annotation_reader.dart` | **Modify.** Parses `/InkList` sub-arrays instead of flattening. |
| `lib/features/viewer/widgets/drawing_surface.dart` | **Modify.** Preview paints every stroke. |
| `lib/domain/models/saved_signature.dart` | **New.** The `SavedSignature` model. |
| `lib/domain/signatures/signature_geometry.dart` | **New.** `normaliseStrokes` and `placeSignature`, pure. |
| `lib/data/local/app_database.dart` | **Modify.** Schema v4: `Signatures` table. |
| `lib/data/local/signature_dao.dart` | **New.** CRUD for signatures. |
| `lib/domain/repositories/signature_repository.dart` | **New.** Interface. |
| `lib/data/repositories/signature_repository_impl.dart` | **New.** Implementation, including stroke JSON. |
| `lib/features/viewer/signature_providers.dart` | **New.** Riverpod state for signing. |
| `lib/features/viewer/widgets/signature_capture_canvas.dart` | **New.** Draw and save a signature. |
| `lib/features/viewer/widgets/signature_sheet.dart` | **New.** List, add, rename, delete. |
| `lib/features/viewer/widgets/signature_placement_surface.dart` | **New.** Drag a box; live fitted preview. |
| `lib/features/viewer/viewer_screen.dart` | **Modify.** `_ViewerMode.signature`. |

---

# Stage 1 — Multi-stroke ink

Ends with: ink carrying several strokes end to end, and the SP-3c joining defect fixed.

---

### Task 1: Ink carries multiple strokes

**Files:**
- Modify: `lib/domain/annotations/drawing_annotation.dart`, `lib/domain/annotations/drawing_appearance.dart`, `lib/domain/annotations/pdf_annotation_writer.dart`, `lib/domain/annotations/pdf_annotation_reader.dart`, `lib/features/viewer/widgets/drawing_surface.dart`
- Test: `test/domain/annotations/multi_stroke_ink_test.dart`

**Interfaces:**
- Produces: `DrawingAnnotation({required DrawingKind kind, required int pageIndex, required List<List<PdfPoint>> strokes, int colorArgb, double strokeWidth})`; `List<PdfPoint> get points => strokes.first`; `DrawingAnnotation.single({...required List<PdfPoint> points...})` convenience constructor

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/multi_stroke_ink_test.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/drawing_appearance.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_annotation_writer.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

const twoStrokes = DrawingAnnotation(
  kind: DrawingKind.ink,
  pageIndex: 0,
  strokes: [
    [PdfPoint(10, 10), PdfPoint(20, 20), PdfPoint(30, 10)],
    [PdfPoint(80, 80), PdfPoint(90, 90), PdfPoint(100, 80)],
  ],
);

Uint8List classicPdf() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\nendobj\n'
    'xref\n0 4\n0000000000 65535 f \n'
    'trailer\n<< /Size 4 /Root 1 0 R >>\n'
    'startxref\n9\n%%EOF\n',
  ),
);

void main() {
  group('geometry', () {
    // Bounding only the first stroke gives a /Rect that is too small and a
    // /BBox that clips most of the signature away.
    test('boundsPt spans every stroke', () {
      final b = twoStrokes.boundsPt;

      expect(b.left, 10);
      expect(b.bottom, 10);
      expect(b.right, 100);
      expect(b.top, 90);
    });

    test('points still reads the first stroke, for shape code', () {
      expect(twoStrokes.points, hasLength(3));
      expect(twoStrokes.points.first.x, 10);
    });

    test('a shape built from two corners still works', () {
      const square = DrawingAnnotation(
        kind: DrawingKind.rectangle,
        pageIndex: 0,
        strokes: [
          [PdfPoint(10, 20), PdfPoint(50, 80)],
        ],
      );

      expect(square.boundsPt.right, 50);
      expect(square.points, hasLength(2));
    });
  });

  group('appearance', () {
    // One moveto per stroke. A single moveto means the strokes are joined by
    // a line through the gap that is not in the document.
    test('emits one subpath per stroke', () {
      final s = drawingAppearanceStream(twoStrokes);

      expect(RegExp(r'\bm\b').allMatches(s).length, 2);
      expect(s, contains('10 10 m'));
      expect(s, contains('80 80 m'));
    });

    test('still strokes the path once', () {
      expect(
        RegExp(r'^S$', multiLine: true)
            .allMatches(drawingAppearanceStream(twoStrokes))
            .length,
        1,
      );
    });
  });

  group('writing', () {
    test('/InkList emits one array per stroke', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [twoStrokes]),
      );

      expect(text, contains('[[10 10 20 20 30 10] [80 80 90 90 100 80]]'));
    });
  });

  group('reading', () {
    // The SP-3c regression: flattening joins strokes when restyled.
    test('a two-stroke /InkList reads back as two strokes', () {
      const doc =
          '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] /Annots [8 0 R] >>\n'
          'endobj\n'
          '8 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [0 0 100 100] '
          '/InkList [[10 10 20 20] [80 80 90 90]] /C [0 0 0] >>\nendobj\n'
          'trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      final ink =
          PdfAnnotationReader.parse(doc).onPage(0).single.reconstructed!
              as DrawingAnnotation;

      expect(ink.strokes, hasLength(2));
      expect(ink.strokes.first, hasLength(2));
      expect(ink.strokes.last.first.x, 80);
    });

    test('a single-stroke /InkList still reads as one stroke', () {
      const doc =
          '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] /Annots [8 0 R] >>\n'
          'endobj\n'
          '8 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [0 0 100 100] '
          '/InkList [[10 10 20 20 30 30]] /C [0 0 0] >>\nendobj\n'
          'trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      final ink =
          PdfAnnotationReader.parse(doc).onPage(0).single.reconstructed!
              as DrawingAnnotation;

      expect(ink.strokes, hasLength(1));
      expect(ink.strokes.single, hasLength(3));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/multi_stroke_ink_test.dart`
Expected: FAIL — `No named parameter with the name 'strokes'`

- [ ] **Step 3: Change the annotation's geometry**

In `lib/domain/annotations/drawing_annotation.dart`, replace the constructor and `points` field:
```dart
final class DrawingAnnotation extends Annotation {
  const DrawingAnnotation({
    required this.kind,
    required this.pageIndex,
    required this.strokes,
    this.colorArgb = 0xFF000000,
    this.strokeWidth = 2,
  });

  /// A shape, or ink drawn in one continuous motion.
  const DrawingAnnotation.single({
    required DrawingKind kind,
    required int pageIndex,
    required List<PdfPoint> points,
    int colorArgb = 0xFF000000,
    double strokeWidth = 2,
  }) : this(
         kind: kind,
         pageIndex: pageIndex,
         strokes: [points],
         colorArgb: colorArgb,
         strokeWidth: strokeWidth,
       );

  final DrawingKind kind;

  @override
  final int pageIndex;

  /// Sub-paths, matching what PDF's /InkList has always meant. Shapes hold a
  /// single sub-path of two corners; a signature holds one per pen stroke.
  final List<List<PdfPoint>> strokes;

  final int colorArgb;
  final double strokeWidth;

  /// The first sub-path. Shapes have only one, so their code reads naturally.
  List<PdfPoint> get points => strokes.first;
```

And make `boundsPt` span every stroke:
```dart
  /// The bounding box in PDF space, across ALL strokes. Bounding only the
  /// first would give a /Rect that is too small and a /BBox that clips the
  /// rest of the drawing away.
  ({double left, double bottom, double right, double top}) get boundsPt {
    final all = strokes.expand((s) => s);
    var left = all.first.x;
    var right = all.first.x;
    var bottom = all.first.y;
    var top = all.first.y;

    for (final p in all) {
      if (p.x < left) left = p.x;
      if (p.x > right) right = p.x;
      if (p.y < bottom) bottom = p.y;
      if (p.y > top) top = p.y;
    }
    return (left: left, bottom: bottom, right: right, top: top);
  }
```

- [ ] **Step 4: Emit one subpath per stroke**

In `lib/domain/annotations/drawing_appearance.dart`, replace the `DrawingKind.ink` case:
```dart
    case DrawingKind.ink:
      for (final stroke in drawing.strokes) {
        if (stroke.length < 2) continue;
        final first = stroke.first;
        buffer.writeln('${pdfNumber(first.x)} ${pdfNumber(first.y)} m');
        for (final s in fitCurve(stroke)) {
          buffer.writeln(
            '${pdfNumber(s.control1.x)} ${pdfNumber(s.control1.y)} '
            '${pdfNumber(s.control2.x)} ${pdfNumber(s.control2.y)} '
            '${pdfNumber(s.end.x)} ${pdfNumber(s.end.y)} c',
          );
        }
      }
      // One S strokes every subpath. A moveto starts a new subpath, so the
      // gaps between strokes stay gaps.
      buffer.writeln('S');
```

- [ ] **Step 5: Write one /InkList array per stroke**

In `lib/domain/annotations/pdf_annotation_writer.dart`, replace the ink geometry case:
```dart
        DrawingKind.ink =>
          ' /InkList [${annotation.strokes.map((stroke) => '[${stroke.map((p) => '${pdfNumber(p.x)} ${pdfNumber(p.y)}').join(' ')}]').join(' ')}]',
```

- [ ] **Step 6: Stop flattening /InkList on read**

In `lib/domain/annotations/pdf_annotation_reader.dart`, add a sub-array reader beside `_numbersIn`:
```dart
  /// The bracketed sub-arrays of [key], each as its own number list.
  ///
  /// /InkList is an array of stroke arrays. Flattening it joins the strokes,
  /// so a regenerated appearance draws a line through every gap.
  static List<List<double>> _subArraysIn(String dict, String key) {
    final open = dict.indexOf('/$key');
    if (open < 0) return const [];
    final start = dict.indexOf('[', open);
    if (start < 0) return const [];

    var depth = 0;
    var end = -1;
    for (var i = start; i < dict.length; i++) {
      if (dict[i] == '[') depth++;
      if (dict[i] == ']') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return const [];

    final inner = dict.substring(start + 1, end);
    final groups = RegExp(r'\[([^\]]*)\]').allMatches(inner).toList();
    final source = groups.isEmpty
        ? [inner]
        : groups.map((m) => m.group(1)!).toList();

    return [
      for (final g in source)
        RegExp(r'-?\d+(?:\.\d+)?')
            .allMatches(g)
            .map((m) => double.parse(m.group(0)!))
            .toList(),
    ];
  }
```

Replace the `'Ink'` case in `_reconstruct`:
```dart
      case 'Ink':
        final groups = _subArraysIn(dict, 'InkList');
        final built = [
          for (final flat in groups)
            [
              for (var i = 0; i + 1 < flat.length; i += 2)
                PdfPoint(flat[i], flat[i + 1]),
            ],
        ].where((s) => s.length >= 2).toList();
        if (built.isEmpty) return null;
        return DrawingAnnotation(
          kind: DrawingKind.ink,
          pageIndex: pageIndex,
          strokes: built,
          colorArgb: colorArgb,
          strokeWidth: strokeWidth,
        );
```

The other cases in `_reconstruct` build shapes; change each `DrawingAnnotation(... points: points ...)` construction at the end of the method to `DrawingAnnotation.single(... points: points ...)`.

- [ ] **Step 7: Paint every stroke in the preview**

In `lib/features/viewer/widgets/drawing_surface.dart`, replace the staged-drawing loop in `paint`:
```dart
    for (final drawing in staged) {
      for (final stroke in drawing.strokes) {
        _drawShape(
          canvas,
          drawing.kind,
          stroke.map(_toCanvas).toList(),
          _paint(drawing.colorArgb, drawing.strokeWidth),
        );
      }
    }
```

- [ ] **Step 8: Fix the remaining construction sites**

Run `flutter analyze --fatal-infos`. Every remaining error is a `DrawingAnnotation(... points: ...)` construction; change each to `DrawingAnnotation.single(...)`. Expect them in `annotation_providers.dart` (`endStroke`), and in the SP-3b and SP-3c test and integration files.

- [ ] **Step 9: Run everything**

Run: `dart format lib test integration_test && flutter analyze --fatal-infos && flutter test`
Expected: all pass, including every SP-3b and SP-3c test. Those suites are the guard that this refactor changed no behaviour for single-stroke drawings.

- [ ] **Step 10: Mutation-test the joining defect**

In `pdf_annotation_reader.dart`, change the `'Ink'` case to flatten again:
```dart
        final built = [groups.expand((g) => g).toList()].map((flat) => [
          for (var i = 0; i + 1 < flat.length; i += 2)
            PdfPoint(flat[i], flat[i + 1]),
        ]).toList();
```
Run `flutter test test/domain/annotations/multi_stroke_ink_test.dart`.

Expected: `a two-stroke /InkList reads back as two strokes` FAILS with one stroke of four points. Revert.

Then in `drawing_annotation.dart`, change `boundsPt`'s `strokes.expand((s) => s)` to `strokes.first`. Run the same file.

Expected: `boundsPt spans every stroke` FAILS with `right` of 30 instead of 100. Revert.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: ink annotations carry multiple strokes

PDF's /InkList is an array of stroke arrays; SP-3b only ever emitted one, so a
drawing was a single polyline. A signature is several disconnected strokes,
which that shape cannot represent without drawing lines through the gaps.

Fixes a live defect in SP-3c: the reader flattened /InkList, so restyling a
multi-stroke ink annotation from another tool regenerated its appearance with
the strokes joined. Probed: [[10 10 20 20] [80 80 90 90]] read back as one
four-point path.

boundsPt now spans every stroke. Bounding only the first gave a /Rect that was
too small and a /BBox that clipped the rest away.

points survives as strokes.first, so the fourteen non-ink uses are untouched."
```

---

# Stage 2 — Storing and placing signatures

Ends with: a signature saved, placed, and rendered into a real PDF.

---

### Task 2: Signature geometry

**Files:**
- Create: `lib/domain/models/saved_signature.dart`, `lib/domain/signatures/signature_geometry.dart`
- Test: `test/domain/signatures/signature_geometry_test.dart`

**Interfaces:**
- Consumes: `PdfPoint`, `TextRect` from `pdf_types.dart`
- Produces: `SavedSignature({required int id, required String label, required List<List<PdfPoint>> strokes, required double aspectRatio})`; `({List<List<PdfPoint>> strokes, double aspectRatio}) normaliseStrokes(List<List<PdfPoint>> captured)`; `List<List<PdfPoint>> placeSignature(SavedSignature signature, {required TextRect box})`

- [ ] **Step 1: Write the failing test**

`test/domain/signatures/signature_geometry_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/domain/signatures/signature_geometry.dart';

SavedSignature sig(List<List<PdfPoint>> strokes, double aspect) =>
    SavedSignature(id: 1, label: 'Full', strokes: strokes, aspectRatio: aspect);

void main() {
  group('normaliseStrokes', () {
    test('maps captured strokes into a unit box', () {
      final result = normaliseStrokes(const [
        [PdfPoint(100, 200), PdfPoint(300, 400)],
      ]);

      final flat = result.strokes.expand((s) => s).toList();
      expect(flat.every((p) => p.x >= 0 && p.x <= 1), isTrue);
      expect(flat.every((p) => p.y >= 0 && p.y <= 1), isTrue);
      expect(flat.first.x, 0);
      expect(flat.last.x, 1);
    });

    test('keeps stroke boundaries', () {
      final result = normaliseStrokes(const [
        [PdfPoint(0, 0), PdfPoint(10, 10)],
        [PdfPoint(20, 0), PdfPoint(30, 10)],
      ]);

      expect(result.strokes, hasLength(2));
    });

    test('reports the aspect ratio of a wide capture', () {
      final result = normaliseStrokes(const [
        [PdfPoint(0, 0), PdfPoint(200, 50)],
      ]);

      expect(result.aspectRatio, closeTo(4, 0.001));
    });

    test('reports the aspect ratio of a tall capture', () {
      final result = normaliseStrokes(const [
        [PdfPoint(0, 0), PdfPoint(50, 200)],
      ]);

      expect(result.aspectRatio, closeTo(0.25, 0.001));
    });

    // A perfectly horizontal stroke has zero height. Dividing by it would
    // produce NaN coordinates and an annotation that renders nowhere.
    test('a zero-height capture does not divide by zero', () {
      final result = normaliseStrokes(const [
        [PdfPoint(0, 50), PdfPoint(100, 50)],
      ]);

      final flat = result.strokes.expand((s) => s).toList();
      expect(flat.every((p) => p.y.isFinite), isTrue);
      expect(result.aspectRatio.isFinite, isTrue);
    });

    test('a single point does not divide by zero', () {
      final result = normaliseStrokes(const [
        [PdfPoint(5, 5)],
      ]);

      expect(result.strokes.single.single.x.isFinite, isTrue);
    });
  });

  group('placeSignature', () {
    final wide = sig(const [
      [PdfPoint(0, 0), PdfPoint(1, 1)],
    ], 2);

    test('fits inside the box', () {
      final placed = placeSignature(
        wide,
        box: const TextRect(left: 100, bottom: 100, right: 300, top: 300),
      );

      final flat = placed.expand((s) => s).toList();
      expect(flat.every((p) => p.x >= 100 && p.x <= 300), isTrue);
      expect(flat.every((p) => p.y >= 100 && p.y <= 300), isTrue);
    });

    // A stretched signature looks forged.
    test('preserves aspect ratio in a box taller than the signature', () {
      final placed = placeSignature(
        wide,
        box: const TextRect(left: 0, bottom: 0, right: 200, top: 200),
      );

      final flat = placed.expand((s) => s).toList();
      final width = flat.last.x - flat.first.x;
      final height = flat.last.y - flat.first.y;
      expect(width / height, closeTo(2, 0.001));
    });

    test('preserves aspect ratio in a box wider than the signature', () {
      final placed = placeSignature(
        wide,
        box: const TextRect(left: 0, bottom: 0, right: 400, top: 100),
      );

      final flat = placed.expand((s) => s).toList();
      final width = flat.last.x - flat.first.x;
      final height = flat.last.y - flat.first.y;
      expect(width / height, closeTo(2, 0.001));
    });

    test('centres the signature within the box', () {
      final placed = placeSignature(
        wide,
        box: const TextRect(left: 0, bottom: 0, right: 200, top: 200),
      );

      final flat = placed.expand((s) => s).toList();
      final top = flat.map((p) => p.y).reduce((a, b) => a > b ? a : b);
      final bottom = flat.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      expect((top + bottom) / 2, closeTo(100, 0.001));
    });

    // Stored strokes are y-up, like PDF. Flipping here puts every signature
    // upside down.
    test('does not flip the y axis', () {
      final placed = placeSignature(
        sig(const [
          [PdfPoint(0, 0), PdfPoint(1, 1)],
        ], 1),
        box: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
      );

      expect(placed.single.last.y, greaterThan(placed.single.first.y));
    });

    test('keeps stroke boundaries', () {
      final placed = placeSignature(
        sig(const [
          [PdfPoint(0, 0), PdfPoint(0.4, 1)],
          [PdfPoint(0.6, 0), PdfPoint(1, 1)],
        ], 1),
        box: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
      );

      expect(placed, hasLength(2));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/signatures/signature_geometry_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Write the model**

`lib/domain/models/saved_signature.dart`:
```dart
import 'package:folio/domain/annotations/pdf_point.dart';

/// A signature the user drew once and can place on any document.
///
/// [strokes] are normalised into a unit box with y increasing upward, matching
/// PDF user space, so placement is a multiply and an offset with no flip.
class SavedSignature {
  const SavedSignature({
    required this.id,
    required this.label,
    required this.strokes,
    required this.aspectRatio,
  });

  final int id;
  final String label;
  final List<List<PdfPoint>> strokes;

  /// Width divided by height as drawn. Placement preserves it: a stretched
  /// signature looks forged.
  final double aspectRatio;
}
```

- [ ] **Step 4: Write the geometry**

`lib/domain/signatures/signature_geometry.dart`:
```dart
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/saved_signature.dart';

/// Maps captured strokes into a unit box, y-up, and reports the aspect ratio
/// they were drawn at.
({List<List<PdfPoint>> strokes, double aspectRatio}) normaliseStrokes(
  List<List<PdfPoint>> captured,
) {
  final all = captured.expand((s) => s).toList();
  if (all.isEmpty) {
    return (strokes: const [], aspectRatio: 1);
  }

  var left = all.first.x;
  var right = all.first.x;
  var bottom = all.first.y;
  var top = all.first.y;
  for (final p in all) {
    if (p.x < left) left = p.x;
    if (p.x > right) right = p.x;
    if (p.y < bottom) bottom = p.y;
    if (p.y > top) top = p.y;
  }

  // A perfectly horizontal stroke has zero height. Dividing by it would give
  // NaN coordinates and an annotation that renders nowhere.
  final width = right - left;
  final height = top - bottom;
  final safeWidth = width == 0 ? 1.0 : width;
  final safeHeight = height == 0 ? 1.0 : height;

  return (
    strokes: [
      for (final stroke in captured)
        [
          for (final p in stroke)
            PdfPoint((p.x - left) / safeWidth, (p.y - bottom) / safeHeight),
        ],
    ],
    aspectRatio: safeWidth / safeHeight,
  );
}

/// Fits [signature] inside [box] preserving its aspect ratio, centred.
List<List<PdfPoint>> placeSignature(
  SavedSignature signature, {
  required TextRect box,
}) {
  final boxWidth = box.right - box.left;
  final boxHeight = box.top - box.bottom;

  // Fit, never fill: whichever dimension runs out first sets the scale.
  var width = boxWidth;
  var height = width / signature.aspectRatio;
  if (height > boxHeight) {
    height = boxHeight;
    width = height * signature.aspectRatio;
  }

  final offsetX = box.left + (boxWidth - width) / 2;
  final offsetY = box.bottom + (boxHeight - height) / 2;

  return [
    for (final stroke in signature.strokes)
      [
        for (final p in stroke)
          PdfPoint(offsetX + p.x * width, offsetY + p.y * height),
      ],
  ];
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/domain/signatures/signature_geometry_test.dart`
Expected: PASS — 13 tests

- [ ] **Step 6: Mutation-test aspect preservation and the y axis**

In `placeSignature`, delete the `if (height > boxHeight)` block so the signature always fills the box width. Run the test file.

Expected: `preserves aspect ratio in a box wider than the signature` FAILS. Revert.

Then change the y term to `offsetY + (1 - p.y) * height`. Run again.

Expected: `does not flip the y axis` FAILS. Revert. Both mutations produce output that still lands inside the box and still looks plausible in every other assertion.

- [ ] **Step 7: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: normalise and place signature strokes

Signatures are stored in a unit box, y-up, so one saved signature works at any
size on any page and placement needs no flip. Placement fits inside the box
rather than filling it: a stretched signature looks forged."
```

---

### Task 3: Signature storage

**Files:**
- Modify: `lib/data/local/app_database.dart`
- Create: `lib/data/local/signature_dao.dart`, `lib/domain/repositories/signature_repository.dart`, `lib/data/repositories/signature_repository_impl.dart`
- Test: `test/data/repositories/signature_repository_test.dart`

**Interfaces:**
- Consumes: `SavedSignature` (Task 2)
- Produces: `SignatureRepository` with `Future<List<SavedSignature>> all()`, `Future<SavedSignature> add({required String label, required List<List<PdfPoint>> strokes, required double aspectRatio})`, `Future<void> rename(int id, String label)`, `Future<void> delete(int id)`

- [ ] **Step 1: Write the failing test**

`test/data/repositories/signature_repository_test.dart`:
```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/signature_dao.dart';
import 'package:folio/data/repositories/signature_repository_impl.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

void main() {
  late AppDatabase db;
  late SignatureRepositoryImpl subject;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    subject = SignatureRepositoryImpl(dao: SignatureDao(db));
  });

  tearDown(() => db.close());

  const strokes = [
    [PdfPoint(0, 0), PdfPoint(0.5, 1)],
    [PdfPoint(0.6, 0), PdfPoint(1, 1)],
  ];

  test('starts empty', () async {
    expect(await subject.all(), isEmpty);
  });

  test('adding returns the stored signature', () async {
    final s = await subject.add(
      label: 'Full',
      strokes: strokes,
      aspectRatio: 2.5,
    );

    expect(s.label, 'Full');
    expect(s.aspectRatio, 2.5);
    expect(s.strokes, hasLength(2));
  });

  // Stroke boundaries are the whole point: flattening them on the way through
  // storage would join the strokes when the signature is placed.
  test('strokes survive a storage round trip with their boundaries', () async {
    await subject.add(label: 'Full', strokes: strokes, aspectRatio: 2.5);

    final loaded = (await subject.all()).single;
    expect(loaded.strokes, hasLength(2));
    expect(loaded.strokes.first, hasLength(2));
    expect(loaded.strokes.last.first.x, closeTo(0.6, 0.0001));
    expect(loaded.strokes.first.last.y, closeTo(1, 0.0001));
  });

  test('renaming changes only the label', () async {
    final s = await subject.add(
      label: 'Full',
      strokes: strokes,
      aspectRatio: 2.5,
    );
    await subject.rename(s.id, 'Initials');

    final loaded = (await subject.all()).single;
    expect(loaded.label, 'Initials');
    expect(loaded.strokes, hasLength(2));
  });

  test('deleting removes it', () async {
    final s = await subject.add(
      label: 'Full',
      strokes: strokes,
      aspectRatio: 2.5,
    );
    await subject.delete(s.id);

    expect(await subject.all(), isEmpty);
  });

  test('several signatures coexist', () async {
    await subject.add(label: 'Full', strokes: strokes, aspectRatio: 2.5);
    await subject.add(label: 'Initials', strokes: strokes, aspectRatio: 1.2);

    expect((await subject.all()).map((s) => s.label), ['Full', 'Initials']);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/repositories/signature_repository_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Add the table and bump the schema**

In `lib/data/local/app_database.dart`, add beside `Collections`:
```dart
/// A signature the user drew once, reusable on any document.
///
/// [strokes] is JSON: a list of stroke point lists, normalised into a unit box
/// with y increasing upward. [kind] and [imageBytes] exist so a photographed
/// signature can land later without migrating what is already stored.
class Signatures extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  TextColumn get kind => text().withDefault(const Constant('drawn'))();
  TextColumn get strokes => text()();
  RealColumn get aspectRatio => real()();
  BlobColumn get imageBytes => blob().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

Change `@DriftDatabase(tables: [Documents, Collections])` to `@DriftDatabase(tables: [Documents, Collections, Signatures])`, change `int get schemaVersion => 3;` to `4`, and extend the migration:
```dart
      if (from < 4) {
        await m.createTable(signatures);
      }
```

Run `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 4: Write the DAO**

`lib/data/local/signature_dao.dart`:
```dart
import 'package:drift/drift.dart';
import 'package:folio/data/local/app_database.dart';

class SignatureDao {
  SignatureDao(this._db);

  final AppDatabase _db;

  Future<List<Signature>> all() {
    final query = _db.select(_db.signatures)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  Future<int> insert({
    required String label,
    required String strokes,
    required double aspectRatio,
  }) => _db
      .into(_db.signatures)
      .insert(
        SignaturesCompanion.insert(
          label: label,
          strokes: strokes,
          aspectRatio: aspectRatio,
        ),
      );

  Future<void> rename(int id, String label) async {
    await (_db.update(_db.signatures)..where((t) => t.id.equals(id))).write(
      SignaturesCompanion(label: Value(label)),
    );
  }

  Future<void> delete(int id) async {
    await (_db.delete(_db.signatures)..where((t) => t.id.equals(id))).go();
  }
}
```

- [ ] **Step 5: Write the repository**

`lib/domain/repositories/signature_repository.dart`:
```dart
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/saved_signature.dart';

abstract interface class SignatureRepository {
  Future<List<SavedSignature>> all();

  Future<SavedSignature> add({
    required String label,
    required List<List<PdfPoint>> strokes,
    required double aspectRatio,
  });

  Future<void> rename(int id, String label);

  Future<void> delete(int id);
}
```

`lib/data/repositories/signature_repository_impl.dart`:
```dart
import 'dart:convert';

import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/signature_dao.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/domain/repositories/signature_repository.dart';

class SignatureRepositoryImpl implements SignatureRepository {
  SignatureRepositoryImpl({required SignatureDao dao}) : _dao = dao;

  final SignatureDao _dao;

  @override
  Future<List<SavedSignature>> all() async =>
      (await _dao.all()).map(_toDomain).toList();

  @override
  Future<SavedSignature> add({
    required String label,
    required List<List<PdfPoint>> strokes,
    required double aspectRatio,
  }) async {
    final id = await _dao.insert(
      label: label,
      strokes: _encode(strokes),
      aspectRatio: aspectRatio,
    );
    return (await all()).firstWhere((s) => s.id == id);
  }

  @override
  Future<void> rename(int id, String label) => _dao.rename(id, label);

  @override
  Future<void> delete(int id) => _dao.delete(id);

  SavedSignature _toDomain(Signature row) => SavedSignature(
    id: row.id,
    label: row.label,
    strokes: _decode(row.strokes),
    aspectRatio: row.aspectRatio,
  );

  /// Stroke boundaries are preserved as nesting. Flattening them here would
  /// join the strokes when the signature is placed.
  static String _encode(List<List<PdfPoint>> strokes) => jsonEncode([
    for (final stroke in strokes)
      [
        for (final p in stroke) {'x': p.x, 'y': p.y},
      ],
  ]);

  static List<List<PdfPoint>> _decode(String json) => [
    for (final stroke in jsonDecode(json) as List)
      [
        for (final p in stroke as List)
          PdfPoint(
            (p as Map<String, dynamic>)['x'] as double,
            p['y'] as double,
          ),
      ],
  ];
}
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/data/repositories/signature_repository_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 7: Run the whole suite — the migration must not break existing rows**

Run: `flutter test`
Expected: all pass.

- [ ] **Step 8: Mutation-test the stroke round trip**

In `_encode`, flatten the strokes: replace its body with
```dart
  static String _encode(List<List<PdfPoint>> strokes) => jsonEncode([
    [
      for (final p in strokes.expand((s) => s)) {'x': p.x, 'y': p.y},
    ],
  ]);
```
Run the test file.

Expected: `strokes survive a storage round trip with their boundaries` FAILS with one stroke instead of two. Revert.

- [ ] **Step 9: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: store saved signatures

Schema v4, additive. Strokes are stored as nested JSON so their boundaries
survive: flattening them would join the strokes when the signature is placed.

The kind and imageBytes columns exist so a photographed signature can land
later without migrating what is already stored."
```

---

# Stage 3 — Signing on the page

Ends with: a signature drawn, saved, placed and rendered, verified on both platforms.

---

### Task 4: Signature capture and management

**Files:**
- Create: `lib/features/viewer/signature_providers.dart`, `lib/features/viewer/widgets/signature_capture_canvas.dart`, `lib/features/viewer/widgets/signature_sheet.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/main.dart`
- Test: `test/features/viewer/signature_controller_test.dart`

**Interfaces:**
- Consumes: `SignatureRepository` (Task 3), `normaliseStrokes` (Task 2), `thinSamples` from `stroke_smoothing.dart`
- Produces: `signatureRepositoryProvider`, `signaturesProvider` (a `FutureProvider<List<SavedSignature>>`), `signingProvider` (a `NotifierProvider<SigningController, SigningState>`) with `select(SavedSignature?)` and `SigningState.chosen`

- [ ] **Step 1: Add the strings**

Append to `lib/l10n/app_en.arb`:
```json
{
  "signMode": "Sign",
  "signChoose": "Choose a signature",
  "signNone": "No signatures yet. Draw one to get started.",
  "signAdd": "New signature",
  "signDraw": "Draw your signature",
  "signClear": "Clear",
  "signSave": "Save signature",
  "signLabel": "Label",
  "signLabelHint": "Full, Initials…",
  "signRename": "Rename",
  "signDelete": "Delete",
  "signPlaceHint": "Drag a box where the signature should go.",
  "signSaved": "Signed {name}",
  "@signSaved": { "placeholders": { "name": { "type": "String" } } },
  "signDiscardPrompt": "Discard this signature placement? The document is unchanged either way."
}
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing controller test**

`test/features/viewer/signature_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/features/viewer/signature_providers.dart';

const one = SavedSignature(
  id: 1,
  label: 'Full',
  strokes: [
    [PdfPoint(0, 0), PdfPoint(1, 1)],
  ],
  aspectRatio: 2,
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  SigningController c() => container.read(signingProvider.notifier);
  SigningState s() => container.read(signingProvider);

  test('starts with nothing chosen', () {
    expect(s().chosen, isNull);
  });

  test('choosing a signature records it', () {
    c().select(one);
    expect(s().chosen?.label, 'Full');
  });

  test('choosing null clears it', () {
    c()
      ..select(one)
      ..select(null);

    expect(s().chosen, isNull);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/viewer/signature_controller_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Write the providers**

`lib/features/viewer/signature_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/domain/repositories/signature_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final signatureRepositoryProvider = Provider<SignatureRepository>(
  (ref) => throw UnimplementedError(
    'signatureRepositoryProvider must be overridden',
  ),
);

final signaturesProvider = FutureProvider<List<SavedSignature>>(
  (ref) => ref.watch(signatureRepositoryProvider).all(),
);

class SigningState {
  const SigningState({this.chosen});

  /// The signature about to be placed, if any.
  final SavedSignature? chosen;
}

final signingProvider = NotifierProvider<SigningController, SigningState>(
  SigningController.new,
);

class SigningController extends Notifier<SigningState> {
  @override
  SigningState build() => const SigningState();

  void select(SavedSignature? signature) =>
      state = SigningState(chosen: signature);
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/viewer/signature_controller_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 6: Build the capture canvas**

`lib/features/viewer/widgets/signature_capture_canvas.dart` — a `StatefulWidget` holding `List<List<Offset>> _strokes`:

- `onPanStart` appends a new empty stroke and adds the point; `onPanUpdate` appends to the last stroke; `onPanEnd` does nothing (the stroke is already complete).
- A `CustomPaint` draws every stroke as a polyline, round caps and joins, 3pt, black on a card background with a baseline hint line.
- **Clear** empties `_strokes`. **Save** is enabled only when at least one stroke has two or more points.
- Save converts canvas offsets to `PdfPoint` with **y flipped once** (`PdfPoint(o.dx, height - o.dy)`), runs each stroke through `thinSamples`, then `normaliseStrokes`, and calls `onSaved(strokes, aspectRatio)`.

The flip belongs here and nowhere else: canvas y grows downward, stored strokes are y-up, and `placeSignature` assumes that.

- [ ] **Step 7: Build the sheet**

`lib/features/viewer/widgets/signature_sheet.dart` — a `ConsumerWidget` shown by `showModalBottomSheet`:

- watches `signaturesProvider`; on empty shows `l10n.signNone`;
- one row per signature: a `CustomPaint` preview drawn from its own strokes (no thumbnail files to keep in sync), the label, and an overflow menu with Rename and Delete;
- tapping a row calls `signingProvider.notifier.select(...)` and pops;
- a **New signature** button opens a dialog containing `SignatureCaptureCanvas` and a label `TextField`, then calls `signatureRepositoryProvider.add(...)` and invalidates `signaturesProvider`.

- [ ] **Step 8: Wire the repository at app start**

In `lib/main.dart`, construct `SignatureRepositoryImpl(dao: SignatureDao(db))` alongside the other repositories and add `signatureRepositoryProvider.overrideWithValue(signatures)` to the `ProviderScope` overrides. The `AppDatabase` instance is already in scope there.

- [ ] **Step 9: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: capture and manage saved signatures

Signatures are previewed by painting their own strokes, so there are no
thumbnail files to keep in sync with the data.

The canvas-to-PDF y flip happens once, at capture: stored strokes are y-up like
PDF user space, and placement assumes it."
```

---

### Task 5: Placing a signature

**Files:**
- Create: `lib/features/viewer/widgets/signature_placement_surface.dart`
- Modify: `lib/features/viewer/viewer_screen.dart`
- Test: `test/features/viewer/signature_placement_test.dart`

**Interfaces:**
- Consumes: `placeSignature` (Task 2), `signingProvider` (Task 4), `canvasToPdf`/`pdfToCanvas` from `page_coordinates.dart`, `AnnotationController` from `annotation_providers.dart`
- Produces: `SignaturePlacementSurface({required Rect pageRect, required double pageWidthPt, required double pageHeightPt, required int pageIndex})`; `AnnotationController.addSignature({required SavedSignature signature, required int pageIndex, required TextRect box})`

- [ ] **Step 1: Write the failing test**

`test/features/viewer/signature_placement_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

const two = SavedSignature(
  id: 1,
  label: 'Full',
  strokes: [
    [PdfPoint(0, 0), PdfPoint(0.4, 1)],
    [PdfPoint(0.6, 0), PdfPoint(1, 1)],
  ],
  aspectRatio: 2,
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationController c() =>
      container.read(annotationSessionProvider.notifier);
  AnnotationState s() => container.read(annotationSessionProvider);

  // One annotation, not one per stroke: deleting a signature must remove the
  // whole thing rather than leaving the other strokes behind.
  test('placing a signature stages exactly one annotation', () {
    c().addSignature(
      signature: two,
      pageIndex: 0,
      box: const TextRect(left: 100, bottom: 100, right: 300, top: 200),
    );

    expect(s().session.annotations, hasLength(1));
  });

  test('the annotation is ink and keeps both strokes', () {
    c().addSignature(
      signature: two,
      pageIndex: 0,
      box: const TextRect(left: 100, bottom: 100, right: 300, top: 200),
    );

    final ink = s().session.annotations.single as DrawingAnnotation;
    expect(ink.kind, DrawingKind.ink);
    expect(ink.strokes, hasLength(2));
  });

  test('the strokes land inside the box', () {
    c().addSignature(
      signature: two,
      pageIndex: 0,
      box: const TextRect(left: 100, bottom: 100, right: 300, top: 200),
    );

    final ink = s().session.annotations.single as DrawingAnnotation;
    final flat = ink.strokes.expand((st) => st).toList();
    expect(flat.every((p) => p.x >= 100 && p.x <= 300), isTrue);
    expect(flat.every((p) => p.y >= 100 && p.y <= 200), isTrue);
  });

  test('placing on page 2 records page 2', () {
    c().addSignature(
      signature: two,
      pageIndex: 2,
      box: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
    );

    expect(s().session.annotations.single.pageIndex, 2);
  });

  test('undo removes the whole signature', () {
    c().addSignature(
      signature: two,
      pageIndex: 0,
      box: const TextRect(left: 0, bottom: 0, right: 100, top: 100),
    );
    c().undo();

    expect(s().session.annotations, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/viewer/signature_placement_test.dart`
Expected: FAIL — `addSignature` is not defined

- [ ] **Step 3: Add the controller method**

In `lib/features/viewer/annotation_providers.dart`, add to `AnnotationController`:
```dart
  /// Stages a saved signature fitted into [box].
  ///
  /// One annotation carrying every stroke, not one per stroke: deleting a
  /// signature must remove the whole thing.
  void addSignature({
    required SavedSignature signature,
    required int pageIndex,
    required TextRect box,
    int colorArgb = 0xFF000000,
    double strokeWidth = 2,
  }) {
    final strokes = placeSignature(signature, box: box);
    if (strokes.isEmpty) return;

    state.session.add(
      DrawingAnnotation(
        kind: DrawingKind.ink,
        pageIndex: pageIndex,
        strokes: strokes,
        colorArgb: colorArgb,
        strokeWidth: strokeWidth,
      ),
    );
    _touch();
  }
```

Add imports for `saved_signature.dart` and `signature_geometry.dart`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/viewer/signature_placement_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 5: Build the placement surface**

`lib/features/viewer/widgets/signature_placement_surface.dart` — a `ConsumerStatefulWidget` holding `Offset? _start` and `Offset? _current`:

- `onPanStart` records the start, `onPanUpdate` the current point, `onPanEnd` commits;
- a `CustomPaint` draws the drag rectangle as a dashed outline, and inside it a live preview of the chosen signature fitted with `placeSignature` and converted back with `pdfToCanvas`, so the preview and the result come from the same function;
- on release it converts both corners with `canvasToPdf`, builds a normalised `TextRect`, and calls `addSignature`:

```dart
  void _commit() {
    final start = _start;
    final current = _current;
    final chosen = ref.read(signingProvider).chosen;
    if (start == null || current == null || chosen == null) return;

    PdfPoint toPdf(Offset o) => canvasToPdf(
      o,
      pageRect: widget.pageRect,
      pageWidthPt: widget.pageWidthPt,
      pageHeightPt: widget.pageHeightPt,
    );

    final a = toPdf(start);
    final b = toPdf(current);
    // Normalised, so dragging up-left works exactly like down-right.
    final box = TextRect(
      left: a.x < b.x ? a.x : b.x,
      right: a.x > b.x ? a.x : b.x,
      bottom: a.y < b.y ? a.y : b.y,
      top: a.y > b.y ? a.y : b.y,
    );

    setState(() {
      _start = null;
      _current = null;
    });

    // A stray tap must not drop a signature nobody can see.
    if (box.right - box.left < 20 || box.top - box.bottom < 20) return;

    ref.read(annotationSessionProvider.notifier).addSignature(
      signature: chosen,
      pageIndex: widget.pageIndex,
      box: box,
    );
  }
```

- [ ] **Step 6: Add the mode to the viewer**

In `lib/features/viewer/viewer_screen.dart`:
- extend `enum _ViewerMode` with `signature` and `_AnnotateTool` with `signature`;
- add a `PopupMenuItem` for `l10n.signMode` with `Icons.draw`;
- `_enterSignatureMode()` calls `ref.read(annotationSessionProvider.notifier).reset()`, shows `SignatureSheet` via `showModalBottomSheet`, and only enters the mode if a signature was chosen — entering with nothing chosen would leave the user in a mode that does nothing;
- `_leaveSignatureMode()` prompts with `l10n.signDiscardPrompt` when the session is dirty, mirroring `_leaveDrawMode`;
- add `signature` to the `leading:` switch;
- extend `pageOverlaysBuilder` with a `signature` branch returning `SignaturePlacementSurface`, passing `Offset.zero & pageRect.size` as it does for the other two;
- show a toolbar in signature mode with the chosen signature's label, `l10n.signPlaceHint`, an undo button, and a pinned Save calling the existing `_saveAnnotations`.

- [ ] **Step 7: Verify on the simulator**

```bash
flutter build ios --simulator --debug
xcrun simctl install DFC5606D-37F0-4176-A73D-B8214C7F820F build/ios/iphonesimulator/Runner.app
xcrun simctl launch DFC5606D-37F0-4176-A73D-B8214C7F820F dev.folio.app
```

Draw a signature with at least two separate strokes, save it, place it by dragging a box, and confirm the strokes are **not** joined. Place it again in a tall box and a wide box and confirm it is not stretched. Save, reopen, and confirm it renders. **Demo this on the simulator.**

Note: any `flutter test integration_test/...` run overwrites `build/ios/iphonesimulator/Runner.app` with the test harness. Rebuild before installing for manual testing or the app launches to a blank screen.

- [ ] **Step 8: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: place a saved signature by dragging a box

The preview and the placed annotation both come from placeSignature, so what
the user sees is what gets written. A drag under 20pt is ignored: a stray tap
must not drop a signature nobody can see.

One annotation carries every stroke, so deleting a signature removes all of it."
```

---

### Task 6: End-to-end verification and documentation

**Files:**
- Create: `integration_test/signature_flow_test.dart`
- Modify: `integration_test/all_tests.dart`, `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`

- [ ] **Step 1: Write the end-to-end flows**

`integration_test/signature_flow_test.dart` builds a real library and a `SignatureRepositoryImpl` over an in-memory database, then asserts by **rendering**:

1. a placed signature draws — render before and after, require more than 500 pixels to differ;
2. **a two-stroke signature leaves a gap** — place a signature whose two strokes sit at opposite ends of the box, then render and assert the pixels along the midpoint column between them are unchanged from the original. This is the assertion that catches joining, and it must fail if the strokes are flattened;
3. a placed signature is **one** annotation — load it back with `AnnotationEditRepositoryImpl` and assert exactly one, whose `/InkList` holds two arrays;
4. deleting it removes the whole signature — after deletion, render and require the page to match the original within 500 pixels;
5. the source document is byte-identical afterwards;
6. a signature placed in a tall box and the same signature in a wide box produce the same aspect ratio, measured from the annotation's `/Rect`.

Register it in `integration_test/all_tests.dart`:
```dart
import 'signature_flow_test.dart' as signature_flow;
// ...
  group('signature_flow', signature_flow.main);
```

- [ ] **Step 2: Run on the iOS simulator**

```bash
flutter test integration_test/all_tests.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including every earlier suite.

Use the aggregate entrypoint, not the directory: `flutter test integration_test` reinstalls and relaunches the app once per file.

- [ ] **Step 3: Run on the Android emulator**

```bash
flutter emulators --launch pixel_api35
flutter test integration_test/all_tests.dart -d emulator-5554
```

Expected: all pass. No Android claim before this.

- [ ] **Step 4: Verify the architectural guards still hold**

```bash
grep -nE "^\s+Future<.*> (write|save|export|materialise)" lib/domain/engine/pdf_engine.dart
```

Expected: no matches.

- [ ] **Step 5: Update the documentation**

- `FEATURES.md` — an SP-3d table for drawing, saving and placing signatures, ✅ where verified and 🟡 for Windows. Note that a placed signature is a normal annotation and can be deleted like any other.
- `LIMITATIONS.md` — photographed signatures are not supported; signatures are not cryptographic and prove nothing about identity; a signature captured small and placed very large may show faceting.
- `ARCHITECTURE.md` — why ink carries strokes rather than points, and that this corrected a defect where restyling a multi-stroke annotation joined its strokes; why signatures are stored normalised y-up.
- `TESTING.md` — refresh counts and the date.

- [ ] **Step 6: Full verification and push**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
git add -A && git commit -m "test: add end-to-end signature flows and update docs

Every flow reopens the output and requires the signature to render. A
two-stroke signature is asserted to leave a gap between its strokes, which is
the assertion that catches flattening."
git push -u origin feature/sp3d-signatures
gh pr create --base develop --title "SP-3d: signatures"
```

Confirm all four CI jobs pass, including `build-windows`.

---

## Definition of done

- [ ] Draw, label, save, rename and delete signatures
- [ ] Place a saved signature by dragging a box, aspect preserved
- [ ] A placed signature is one annotation and deletes as one
- [ ] Multi-stroke ink round-trips without joining, proven by mutation
- [ ] Every SP-3b and SP-3c test still passes
- [ ] `PdfEngine` still has no write method
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

**Next:** SP-3e — sticky notes and stamps — then SP-3f — moving and resizing annotations.
