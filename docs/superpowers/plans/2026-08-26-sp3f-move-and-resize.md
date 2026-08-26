# SP-3f — Moving and Resizing Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drag a saved annotation to move it, and drag its corners to resize it.

**Architecture:** Moving is a `/Rect` rewrite plus one affine over the coordinate-pair geometry keys, applied to the raw dictionary — no reconstruction, and no appearance regeneration, because PDFium maps an appearance `/BBox` onto its `/Rect`. Moves are staged alongside deletes and restyles in the existing edit session, and an annotation that is both moved and restyled emits a single combined override.

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5, pdfrx 2.4.7 (PDFium), drift 2.34.3, flutter_riverpod 3.3.2.

**Spec:** `docs/superpowers/specs/2026-08-26-sp3f-move-and-resize-design.md`

## Global Constraints

- **Zero AI, zero paid or proprietary SDKs, no GPL/LGPL/AGPL.** No new dependencies.
- **Never destroy originals.** Saving goes through the existing repository, which rewrites only Folio-created documents in place and otherwise writes a new one.
- **`PdfEngine` has no write method and must not gain one.**
- **`PdfObjectReader` handles page dictionaries and nothing else.**
- **Never log document content, passwords, filenames or paths.**
- **Folio stamps no `/Producer`, no `/ModDate`, and no ownership marker.**
- **A feature is not done until it has been verified by rendering.**
- Run `dart format lib test integration_test scripts` and `flutter analyze --fatal-infos` before every commit.

## Critical context the implementer will not guess

**No appearance is regenerated.** Probed on device 2026-08-26: changing only `/Rect` moved a mark from columns 20..59 to 200..239, enlarging `/Rect` scaled it from 40 to 120 columns, and both held even when the `/BBox` was in page coordinates as Folio's drawings are. PDFium implements the §12.5.5 BBox→Rect mapping, so the existing `/AP` follows the new rect for free.

**Geometry must be rewritten anyway.** Rewriting `/Rect` alone renders correctly *today* but leaves `/InkList`, `/L` and `/QuadPoints` pointing at the old position, so a later restyle regenerates the appearance back where the annotation started — two actions apart and invisible in between. `/Rect` and geometry are always rewritten together.

**This is a stated exception to SP-3c's verbatim rule**, which still holds for restyling. A move is the one operation that *is* a request to change geometry.

**One override per object number.** `applyAnnotationEdits` currently loops restyles and emits an override each. Adding a second loop for moves would emit a second override of the same object, and in an incremental update the later one wins — so one of the two changes would vanish depending on loop order. Walk the **union** of moved and restyled object numbers once.

**Restyling requires reconstruction; moving does not.** The restyle loop skips when `target.reconstructed == null`, which is why a stamp is delete-only. Moving works on the raw dictionary, so a stamp moves fine. Do not gate moves on reconstruction.

## File structure

| File | Responsibility |
|---|---|
| `lib/domain/annotations/annotation_transform.dart` | **New.** `transformPoint`, `transformAnnotationDict`, `lockAspect`. |
| `lib/domain/annotations/pdf_annotation_reader.dart` | **Modify.** `movable` and `resizable` on `SavedAnnotation`. |
| `lib/domain/annotations/annotation_edit_session.dart` | **Modify.** `moveTo`, `moved`, `isDirty`, undo. |
| `lib/domain/annotations/pdf_annotation_editor.dart` | **Modify.** `moved` parameter; union loop; single override. |
| `lib/domain/repositories/annotation_edit_repository.dart` | **Modify.** `save` gains `moved`. |
| `lib/data/repositories/annotation_edit_repository_impl.dart` | **Modify.** Passes it through; guard counts moves. |
| `lib/features/viewer/annotation_edit_providers.dart` | **Modify.** `moveSelected`. |
| `lib/features/viewer/widgets/annotation_selection_overlay.dart` | **Modify.** Drag to move, corner handles, live outline. |
| `lib/features/viewer/viewer_screen.dart` | **Modify.** Passes `moved` to save. |

---

# Stage 1 — The transform

Ends with: a dictionary that can be moved and stays internally consistent.

---

### Task 1: The geometry transform

**Files:**
- Create: `lib/domain/annotations/annotation_transform.dart`
- Modify: `lib/domain/annotations/pdf_annotation_reader.dart`
- Test: `test/domain/annotations/annotation_transform_test.dart`

**Interfaces:**
- Consumes: `PdfPoint`, `TextRect` from `pdf_types.dart`, `pdfNumber` from `pdf_appearance.dart`
- Produces: `PdfPoint transformPoint(PdfPoint p, {required TextRect from, required TextRect to})`; `String transformAnnotationDict(String dict, {required TextRect from, required TextRect to})`; `TextRect lockAspect(TextRect proposed, {required TextRect original})`; and on `SavedAnnotation`, `bool get movable` and `bool get resizable`

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/annotation_transform_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation_transform.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

const from = TextRect(left: 0, bottom: 0, right: 100, top: 100);
const shifted = TextRect(left: 200, bottom: 300, right: 300, top: 400);
const doubled = TextRect(left: 0, bottom: 0, right: 200, top: 200);

SavedAnnotation annotationOf(String subtype) => SavedAnnotation(
  objectNumber: 7,
  pageIndex: 0,
  subtype: subtype,
  rectPt: from,
  rawDictionary: '<< >>',
);

void main() {
  group('transformPoint', () {
    test('maps each corner onto the corresponding corner', () {
      expect(
        transformPoint(const PdfPoint(0, 0), from: from, to: shifted).x,
        200,
      );
      expect(
        transformPoint(const PdfPoint(0, 0), from: from, to: shifted).y,
        300,
      );
      expect(
        transformPoint(const PdfPoint(100, 100), from: from, to: shifted).x,
        300,
      );
      expect(
        transformPoint(const PdfPoint(100, 100), from: from, to: shifted).y,
        400,
      );
    });

    test('scales interior points', () {
      final p = transformPoint(
        const PdfPoint(50, 50),
        from: from,
        to: doubled,
      );
      expect(p.x, 100);
      expect(p.y, 100);
    });

    // A zero-width rect would divide by zero and produce NaN coordinates,
    // which render nowhere at all.
    test('a zero-area source does not divide by zero', () {
      const flat = TextRect(left: 10, bottom: 10, right: 10, top: 10);
      final p = transformPoint(const PdfPoint(10, 10), from: flat, to: shifted);

      expect(p.x.isFinite, isTrue);
      expect(p.y.isFinite, isTrue);
    });
  });

  group('transformAnnotationDict', () {
    const inkDict =
        '<< /Type /Annot /Subtype /Ink /Rect [0 0 100 100] '
        '/InkList [[0 0 50 50] [100 100 0 100]] /C [1 0 0] /CA 1 /F 4 '
        '/BS << /W 3 >> /AP << /N 9 0 R >> >>';

    test('rewrites /Rect', () {
      final out = transformAnnotationDict(inkDict, from: from, to: shifted);
      expect(out, contains('/Rect [200 300 300 400]'));
    });

    // Rewriting /Rect alone leaves geometry pointing at the old position, so a
    // later restyle regenerates the appearance back where it started.
    test('rewrites /InkList by the same affine', () {
      final out = transformAnnotationDict(inkDict, from: from, to: shifted);
      expect(out, contains('/InkList [[200 300 250 350] [300 400 200 400]]'));
    });

    test('rewrites /L for a line', () {
      const lineDict =
          '<< /Type /Annot /Subtype /Line /Rect [0 0 100 100] '
          '/L [0 0 100 100] >>';
      final out = transformAnnotationDict(lineDict, from: from, to: shifted);

      expect(out, contains('/L [200 300 300 400]'));
    });

    test('rewrites /QuadPoints', () {
      const markupDict =
          '<< /Type /Annot /Subtype /Highlight /Rect [0 0 100 100] '
          '/QuadPoints [0 100 100 100 0 0 100 0] >>';
      final out = transformAnnotationDict(markupDict, from: from, to: shifted);

      expect(out, contains('/QuadPoints [200 400 300 400 200 300 300 300]'));
    });

    // A note or a stamp has no geometry key; /Rect is the whole story.
    test('a dictionary with no geometry key changes only its /Rect', () {
      const noteDict =
          '<< /Type /Annot /Subtype /Text /Rect [0 0 100 100] '
          '/Contents (Hello) /Name /Note >>';
      final out = transformAnnotationDict(noteDict, from: from, to: shifted);

      expect(out, contains('/Rect [200 300 300 400]'));
      expect(out, contains('/Contents (Hello)'));
    });

    test('colour, width and the appearance reference all survive', () {
      final out = transformAnnotationDict(inkDict, from: from, to: shifted);

      expect(out, contains('/C [1 0 0]'));
      expect(out, contains('/BS << /W 3 >>'));
      expect(out, contains('/AP << /N 9 0 R >>'));
    });

    test('a zero-area source returns the dictionary unchanged', () {
      const flat = TextRect(left: 10, bottom: 10, right: 10, top: 10);
      expect(
        transformAnnotationDict(inkDict, from: flat, to: shifted),
        inkDict,
      );
    });
  });

  group('lockAspect', () {
    const original = TextRect(left: 0, bottom: 0, right: 200, top: 100);

    test('preserves the ratio when the drag is too tall', () {
      final locked = lockAspect(
        const TextRect(left: 0, bottom: 0, right: 200, top: 400),
        original: original,
      );

      expect(
        (locked.right - locked.left) / (locked.top - locked.bottom),
        closeTo(2, 0.001),
      );
    });

    test('preserves the ratio when the drag is too wide', () {
      final locked = lockAspect(
        const TextRect(left: 0, bottom: 0, right: 800, top: 100),
        original: original,
      );

      expect(
        (locked.right - locked.left) / (locked.top - locked.bottom),
        closeTo(2, 0.001),
      );
    });

    test('keeps the top-left corner anchored', () {
      final locked = lockAspect(
        const TextRect(left: 50, bottom: 0, right: 250, top: 400),
        original: original,
      );

      expect(locked.left, 50);
      expect(locked.top, 400);
    });
  });

  group('what may be moved', () {
    test('markup is anchored to its words', () {
      for (final subtype in ['Highlight', 'Underline', 'StrikeOut']) {
        expect(annotationOf(subtype).movable, isFalse, reason: subtype);
        expect(annotationOf(subtype).resizable, isFalse, reason: subtype);
      }
    });

    test('drawings, notes and stamps move', () {
      for (final subtype in ['Ink', 'Square', 'Circle', 'Line', 'Text',
        'Stamp']) {
        expect(annotationOf(subtype).movable, isTrue, reason: subtype);
      }
    });

    // Every viewer draws a /Text icon at a fixed size, so there is nothing for
    // a resize to change.
    test('a note moves but does not resize', () {
      expect(annotationOf('Text').movable, isTrue);
      expect(annotationOf('Text').resizable, isFalse);
    });

    test('a stamp resizes even though it cannot be restyled', () {
      final stamp = annotationOf('Stamp');

      expect(stamp.restylable, isFalse);
      expect(stamp.resizable, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/annotation_transform_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement the transform**

`lib/domain/annotations/annotation_transform.dart`:
```dart
import 'package:folio/domain/annotations/pdf_appearance.dart' show pdfNumber;
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// The geometry keys that hold flat lists of x-y pairs in page space.
///
/// /InkList nests one array per stroke, but the pairs are positional either
/// way, so the same transform applies without knowing the structure.
const _geometryKeys = ['InkList', 'QuadPoints', 'L', 'Vertices'];

/// Maps [p] from the [from] rect into the [to] rect.
PdfPoint transformPoint(
  PdfPoint p, {
  required TextRect from,
  required TextRect to,
}) {
  final fromWidth = from.right - from.left;
  final fromHeight = from.top - from.bottom;
  // A zero-area source would divide by zero and give NaN coordinates, which
  // render nowhere at all.
  if (fromWidth == 0 || fromHeight == 0) return p;

  final scaleX = (to.right - to.left) / fromWidth;
  final scaleY = (to.top - to.bottom) / fromHeight;

  return PdfPoint(
    to.left + (p.x - from.left) * scaleX,
    to.bottom + (p.y - from.bottom) * scaleY,
  );
}

/// Rewrites `/Rect` and every coordinate-pair geometry key in [dict] so they
/// agree after the annotation moves from [from] to [to].
///
/// Rewriting `/Rect` alone would render correctly - a viewer maps the
/// appearance onto the rect - but leave the geometry pointing at the old
/// position, so a later restyle regenerates the appearance where the
/// annotation used to be. They move together or not at all.
String transformAnnotationDict(
  String dict, {
  required TextRect from,
  required TextRect to,
}) {
  if (from.right - from.left == 0 || from.top - from.bottom == 0) return dict;

  var out = dict.replaceFirst(
    RegExp(r'/Rect\s*\[[^\]]*\]'),
    '/Rect [${pdfNumber(to.left)} ${pdfNumber(to.bottom)} '
        '${pdfNumber(to.right)} ${pdfNumber(to.top)}]',
  );

  for (final key in _geometryKeys) {
    final match = RegExp('/$key\\s*(\\[.*?\\])(?=\\s*/|\\s*>>)', dotAll: true)
        .firstMatch(out);
    if (match == null) continue;

    final rewritten = _transformNumbers(match.group(1)!, from: from, to: to);
    out = out.replaceRange(match.start, match.end, '/$key $rewritten');
  }

  return out;
}

/// Rewrites every x-y pair inside a bracketed value, preserving its nesting
/// and any surrounding punctuation.
String _transformNumbers(
  String source, {
  required TextRect from,
  required TextRect to,
}) {
  final numbers = RegExp(r'-?\d+(?:\.\d+)?');
  final values = numbers
      .allMatches(source)
      .map((m) => double.parse(m.group(0)!))
      .toList();

  final moved = <double>[];
  for (var i = 0; i + 1 < values.length; i += 2) {
    final p = transformPoint(
      PdfPoint(values[i], values[i + 1]),
      from: from,
      to: to,
    );
    moved..add(p.x)..add(p.y);
  }
  // An odd trailing number is not part of a pair; leave it as it was.
  if (values.length.isOdd) moved.add(values.last);

  var index = 0;
  return source.replaceAllMapped(
    numbers,
    (_) => pdfNumber(moved[index++]),
  );
}

/// The rect [proposed] becomes once its aspect ratio is locked to [original].
///
/// The top-left corner stays put, so the annotation grows away from where the
/// user started the drag rather than jumping.
TextRect lockAspect(TextRect proposed, {required TextRect original}) {
  final ratio =
      (original.right - original.left) / (original.top - original.bottom);
  if (!ratio.isFinite || ratio == 0) return proposed;

  var width = proposed.right - proposed.left;
  var height = proposed.top - proposed.bottom;

  // Fit inside the drag, never outside it.
  if (width / height > ratio) {
    width = height * ratio;
  } else {
    height = width / ratio;
  }

  return TextRect(
    left: proposed.left,
    top: proposed.top,
    right: proposed.left + width,
    bottom: proposed.top - height,
  );
}
```

- [ ] **Step 4: Add movable and resizable**

In `lib/domain/annotations/pdf_annotation_reader.dart`, add to `SavedAnnotation`:
```dart
  /// Text markup is anchored to the words it covers, so moving it is
  /// meaningless.
  bool get movable =>
      subtype != 'Highlight' &&
      subtype != 'Underline' &&
      subtype != 'StrikeOut';

  /// Every viewer draws a /Text icon at a fixed size, so there is nothing for
  /// a resize to change.
  bool get resizable => movable && subtype != 'Text';
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/domain/annotations/annotation_transform_test.dart`
Expected: PASS — 17 tests

- [ ] **Step 6: Mutation-test the geometry rewrite and the aspect lock**

In `transformAnnotationDict`, delete the `for (final key in _geometryKeys)` loop so only `/Rect` is rewritten. Run the test file.

Expected: `rewrites /InkList by the same affine`, `rewrites /L for a line` and `rewrites /QuadPoints` all FAIL. Revert. This mutation is exactly the "rect only" design that renders correctly today and breaks two actions later.

Then in `lockAspect`, replace the body with `return proposed;`. Run again.

Expected: both aspect tests FAIL. Revert.

- [ ] **Step 7: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: transform an annotation's rect and geometry together

Moving rewrites /Rect and every coordinate-pair geometry key by the same
affine. Rewriting /Rect alone renders correctly - a viewer maps the appearance
onto the rect - but leaves geometry pointing at the old position, so a later
restyle regenerates the appearance where the annotation used to be.

Works on the raw dictionary, so a stamp moves even though Folio cannot
reconstruct one well enough to restyle it."
```

---

# Stage 2 — Staging and writing moves

Ends with: a move saved into a real PDF, alone or alongside a restyle.

---

### Task 2: Staging moves and writing them

**Files:**
- Modify: `lib/domain/annotations/annotation_edit_session.dart`, `lib/domain/annotations/pdf_annotation_editor.dart`, `lib/domain/repositories/annotation_edit_repository.dart`, `lib/data/repositories/annotation_edit_repository_impl.dart`
- Test: `test/domain/annotations/annotation_edit_session_test.dart`, `test/domain/annotations/pdf_annotation_editor_test.dart`

**Interfaces:**
- Consumes: `transformAnnotationDict` (Task 1)
- Produces: `AnnotationEditSession.moveTo(int objectNumber, TextRect rect)` and `Map<int, TextRect> get moved`; `applyAnnotationEdits(Uint8List pdf, {required Set<int> deleted, required Map<int, AnnotationStyle> restyled, required Map<int, TextRect> moved})`; `AnnotationEditRepository.save({required int documentId, required Set<int> deleted, required Map<int, AnnotationStyle> restyled, required Map<int, TextRect> moved})`

- [ ] **Step 1: Add the failing session tests**

Append to `test/domain/annotations/annotation_edit_session_test.dart`:
```dart
  group('moving', () {
    const target = TextRect(left: 200, bottom: 300, right: 300, top: 400);

    test('staging a move makes the session dirty', () {
      final s = AnnotationEditSession([saved(7)])..moveTo(7, target);

      expect(s.moved[7], target);
      expect(s.isDirty, isTrue, reason: 'Save must not stay disabled');
    });

    test('moving twice keeps only the latest rect', () {
      final s = AnnotationEditSession([saved(7)])
        ..moveTo(7, target)
        ..moveTo(
          7,
          const TextRect(left: 0, bottom: 0, right: 10, top: 10),
        );

      expect(s.moved[7]!.right, 10);
      expect(s.moved, hasLength(1));
    });

    // A move staged for something about to be unreferenced is dead weight.
    test('deleting a moved annotation drops its staged move', () {
      final s = AnnotationEditSession([saved(7)])
        ..moveTo(7, target)
        ..delete(7);

      expect(s.moved, isEmpty);
      expect(s.deleted, {7});
    });

    test('undo reverses a move', () {
      final s = AnnotationEditSession([saved(7)])..moveTo(7, target);
      s.undo();

      expect(s.moved, isEmpty);
      expect(s.isDirty, isFalse);
    });

    test('undo crosses moves and restyles in order', () {
      final s = AnnotationEditSession([saved(7)])
        ..restyle(7, red)
        ..moveTo(7, target);

      s.undo();
      expect(s.moved, isEmpty);
      expect(s.restyled[7], red);

      s.undo();
      expect(s.restyled, isEmpty);
      expect(s.isDirty, isFalse);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/annotation_edit_session_test.dart`
Expected: FAIL — `moveTo` is not defined

- [ ] **Step 3: Stage moves in the session**

In `lib/domain/annotations/annotation_edit_session.dart`, add the field and widen the snapshot record:
```dart
  Map<int, TextRect> _moved = {};
  final List<
    ({
      Set<int> deleted,
      Map<int, AnnotationStyle> restyled,
      Map<int, TextRect> moved,
    })
  >
  _undo = [];
```

Update `_snapshot`, `isDirty` and `undo`:
```dart
  void _snapshot() {
    _undo.add((
      deleted: Set.of(_deleted),
      restyled: Map.of(_restyled),
      moved: Map.of(_moved),
    ));
  }

  bool get isDirty =>
      _deleted.isNotEmpty || _restyled.isNotEmpty || _moved.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    _deleted = previous.deleted;
    _restyled = previous.restyled;
    _moved = previous.moved;
  }
```

Add the accessor and the operation, and drop a staged move on delete:
```dart
  Map<int, TextRect> get moved => Map.unmodifiable(_moved);

  void moveTo(int objectNumber, TextRect rect) {
    _snapshot();
    _moved = {..._moved, objectNumber: rect};
  }
```

In `delete`, alongside the existing style removal:
```dart
    _moved = {..._moved}..remove(objectNumber);
```

Add `import 'package:folio/domain/engine/pdf_types.dart';`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/annotation_edit_session_test.dart`
Expected: PASS — the SP-3c tests plus 5 new.

- [ ] **Step 5: Add the failing editor tests**

Append to `test/domain/annotations/pdf_annotation_editor_test.dart`:
```dart
  group('moving', () {
    Uint8List withInk() => Uint8List.fromList(
      latin1.encode(
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Annots [7 0 R] >>\nendobj\n'
        '7 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [0 0 100 100] '
        '/InkList [[0 0 100 100]] /C [1 0 0] /CA 1 /F 4 /BS << /W 3 >> '
        '/AP << /N 6 0 R >> >>\nendobj\n'
        'xref\n0 8\n0000000000 65535 f \n'
        'trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
      ),
    );

    const target = TextRect(left: 200, bottom: 300, right: 300, top: 400);

    String overrideOf(Uint8List out) => RegExp(
      r'7 0 obj\s*(<<.*?>>)\s*endobj',
      dotAll: true,
    ).allMatches(latin1.decode(out)).last.group(1)!;

    test('rewrites /Rect and /InkList together', () {
      final o = overrideOf(
        applyAnnotationEdits(
          withInk(),
          deleted: const {},
          restyled: const {},
          moved: {7: target},
        ),
      );

      expect(o, contains('/Rect [200 300 300 400]'));
      expect(o, contains('/InkList [[200 300 300 400]]'));
    });

    // The appearance follows /Rect, so regenerating it would be wasted work
    // and a chance to disagree with what is already there.
    test('emits no new appearance stream', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          withInk(),
          deleted: const {},
          restyled: const {},
          moved: {7: target},
        ),
      );

      expect(text, isNot(contains('/Subtype /Form')));
      expect(overrideOf(Uint8List.fromList(text.codeUnits)),
          contains('/AP << /N 6 0 R >>'));
    });

    test('nothing staged returns the input unchanged', () {
      final original = withInk();
      expect(
        applyAnnotationEdits(
          original,
          deleted: const {},
          restyled: const {},
          moved: const {},
        ),
        original,
      );
    });

    // Two overrides of one object mean the later wins and the earlier vanishes.
    test('a moved AND restyled annotation emits exactly one override', () {
      final out = applyAnnotationEdits(
        withInk(),
        deleted: const {},
        restyled: {
          7: const AnnotationStyle(colorArgb: 0xFF0000FF, strokeWidth: 8),
        },
        moved: {7: target},
      );
      final text = latin1.decode(out);

      // Original plus exactly one override.
      expect(RegExp(r'7 0 obj').allMatches(text).length, 2);

      final o = overrideOf(out);
      expect(o, contains('/Rect [200 300 300 400]'), reason: 'the move');
      expect(o, contains('/C [0 0 1]'), reason: 'the restyle');
      expect(o, contains('/W 8'), reason: 'the restyle');
    });

    test('a move alone leaves colour and width untouched', () {
      final o = overrideOf(
        applyAnnotationEdits(
          withInk(),
          deleted: const {},
          restyled: const {},
          moved: {7: target},
        ),
      );

      expect(o, contains('/C [1 0 0]'));
      expect(o, contains('/BS << /W 3 >>'));
    });
  });
```

Add `import 'package:folio/domain/engine/pdf_types.dart';` to the test file.

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_annotation_editor_test.dart`
Expected: FAIL — `applyAnnotationEdits` has no `moved` parameter

- [ ] **Step 7: Walk the union once**

In `lib/domain/annotations/pdf_annotation_editor.dart`, add the parameter and widen the early return:
```dart
Uint8List applyAnnotationEdits(
  Uint8List pdf, {
  required Set<int> deleted,
  required Map<int, AnnotationStyle> restyled,
  required Map<int, TextRect> moved,
}) {
  if (deleted.isEmpty && restyled.isEmpty && moved.isEmpty) return pdf;
```

Replace the `for (final entry in restyled.entries)` loop with a union walk:
```dart
  // The union, walked once. Emitting a second override of the same object
  // number means the later one wins and the earlier change vanishes.
  final touched = {...restyled.keys, ...moved.keys};
  for (final objectNumber in touched) {
    final target = _find(saved, objectNumber);
    if (target == null) continue;

    final destinationRect = moved[objectNumber];
    final requestedStyle = restyled[objectNumber];
    // A restyle we cannot honour - no reconstruction, so no appearance to
    // regenerate - and no move either means there is nothing to write. The
    // old code skipped these; emitting an identical override would append an
    // xref and a trailer for no change at all.
    if (destinationRect == null &&
        (requestedStyle == null || target.reconstructed == null)) {
      continue;
    }

    // The move applies to the raw dictionary and needs no reconstruction,
    // which is why a stamp can move even though it cannot be restyled.
    var dict = target.rawDictionary;
    if (destinationRect != null) {
      dict = transformAnnotationDict(
        dict,
        from: target.rectPt,
        to: destinationRect,
      );
    }

    final style = requestedStyle;
    if (style == null) {
      emit(objectNumber, dict);
      continue;
    }

    // Restyling regenerates the appearance, which needs reconstruction.
    if (target.reconstructed == null) {
      emit(objectNumber, dict);
      continue;
    }

    final restyledAnnotation = _withStyle(target.reconstructed!, style);

    int? apNum;
    if (restyledAnnotation is! StickyNote) {
      final (stream, apDict) = switch (restyledAnnotation) {
        TextMarkup() => (
          appearanceStream(restyledAnnotation),
          appearanceDict(
            restyledAnnotation,
            appearanceStream(restyledAnnotation).length,
          ),
        ),
        DrawingAnnotation() => (
          drawingAppearanceStream(restyledAnnotation),
          drawingAppearanceDict(
            restyledAnnotation,
            drawingAppearanceStream(restyledAnnotation).length,
          ),
        ),
        StickyNote() || Stamp() => throw StateError('unreachable'),
      };
      apNum = nextObj++;
      emit(apNum, '$apDict\nstream\n${stream}endstream');
    }

    emit(objectNumber, _restyledDictionary(dict, style, apNum));
  }
```

Note that `_restyledDictionary` is now given the **transformed** dictionary, so
a move and a restyle compose into one override.

Add imports for `annotation_transform.dart` and `pdf_types.dart`.

- [ ] **Step 8: Widen the repository**

In `lib/domain/repositories/annotation_edit_repository.dart`:
```dart
  Future<LibraryDocument> save({
    required int documentId,
    required Set<int> deleted,
    required Map<int, AnnotationStyle> restyled,
    required Map<int, TextRect> moved,
  });
```

In `lib/data/repositories/annotation_edit_repository_impl.dart`, add the
parameter, widen the guard, and pass it through:
```dart
    if (deleted.isEmpty && restyled.isEmpty && moved.isEmpty) {
      throw ArgumentError('nothing to save');
    }
    …
    final edited = applyAnnotationEdits(
      bytes,
      deleted: deleted,
      restyled: restyled,
      moved: moved,
    );
```

Add `import 'package:folio/domain/engine/pdf_types.dart';` to both.

The analyzer will now name every other caller. Pass `moved: const {}` at each
existing call site in tests and in `viewer_screen.dart`.

- [ ] **Step 9: Run to verify it passes**

Run: `dart format lib test integration_test && flutter analyze --fatal-infos && flutter test`
Expected: all pass, including every SP-3c and SP-3e test.

- [ ] **Step 10: Mutation-test the single override**

In the union walk, change `final touched = {...restyled.keys, ...moved.keys};`
to `final touched = restyled.keys.toList();` and add a second loop after it that
emits a move-only override for each entry in `moved`. Run the editor test file.

Expected: `a moved AND restyled annotation emits exactly one override` FAILS
with three `7 0 obj` occurrences instead of two. Revert.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: stage and write annotation moves

applyAnnotationEdits walks the union of moved and restyled object numbers once
and emits a single override each. Two overrides of one object number mean the
later wins, so a move and a restyle on the same annotation would lose one of
the two depending on loop order.

A move needs no reconstruction, so a stamp moves even though it cannot be
restyled. No appearance is regenerated: the existing one follows /Rect."
```

---

# Stage 3 — Dragging, and verification

Ends with: annotations moved and resized on device, proven by rendering.

---

### Task 3: Drag and handles

**Files:**
- Modify: `lib/features/viewer/annotation_edit_providers.dart`, `lib/features/viewer/widgets/annotation_selection_overlay.dart`, `lib/features/viewer/viewer_screen.dart`
- Test: `test/features/viewer/annotation_edit_controller_test.dart`

**Interfaces:**
- Consumes: `lockAspect` (Task 1), `AnnotationEditSession.moveTo` (Task 2), `canvasToPdf`/`pdfToCanvas` from `page_coordinates.dart`
- Produces: `AnnotationEditController.moveSelected(TextRect rect)`

- [ ] **Step 1: Add the failing controller test**

Append to `test/features/viewer/annotation_edit_controller_test.dart`:
```dart
  group('moving', () {
    const target = TextRect(left: 200, bottom: 300, right: 300, top: 400);

    test('moving the selection stages a rect', () {
      c()
        ..loadInto([saved(7)])
        ..select(7)
        ..moveSelected(target);

      expect(s().session.moved[7], target);
    });

    test('moving with nothing selected does nothing', () {
      c()
        ..loadInto([saved(7)])
        ..moveSelected(target);

      expect(s().session.isDirty, isFalse);
    });

    // The selection outline must follow the annotation to its new home, or the
    // user cannot tell the move registered.
    test('the annotation stays selected after a move', () {
      c()
        ..loadInto([saved(7)])
        ..select(7)
        ..moveSelected(target);

      expect(s().selectedObjectNumber, 7);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/viewer/annotation_edit_controller_test.dart`
Expected: FAIL — `moveSelected` is not defined

- [ ] **Step 3: Add the controller method**

In `lib/features/viewer/annotation_edit_providers.dart`:
```dart
  /// Stages a new rect for the selection. The selection is kept: the outline
  /// must follow the annotation, or the user cannot tell the move registered.
  void moveSelected(TextRect rect) {
    final selected = state.selectedObjectNumber;
    if (selected == null) return;
    state.session.moveTo(selected, rect);
    _touch();
  }
```

Add `import 'package:folio/domain/engine/pdf_types.dart';`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/viewer/annotation_edit_controller_test.dart`
Expected: PASS — the SP-3c tests plus 3 new.

- [ ] **Step 5: Add dragging and handles to the overlay**

In `lib/features/viewer/widgets/annotation_selection_overlay.dart`:

- the widget becomes a `ConsumerStatefulWidget` holding `Rect? _liveRect` and
  `int? _activeHandle` (0..3 for the corners, null when moving the whole rect);
- `effectiveRect(SavedAnnotation a)` returns the staged move from
  `session.moved[a.objectNumber]` if present, else `a.rectPt`, converted with
  `canvasRectOf` — so the outline and the handles sit where the annotation now
  is, not where it started;
- `onPanStart` decides the gesture: within 24 logical pixels of a corner and
  `a.resizable` starts a resize on that corner, otherwise a hit inside the rect
  and `a.movable` starts a move. A pan that starts on neither does nothing;
- `onPanUpdate` updates `_liveRect`. A resize moves only the dragged corner; a
  move translates the whole rect. When the annotation is ink or a stamp, run
  the result through `lockAspect`;
- `onPanEnd` converts `_liveRect` back to PDF space and commits:

```dart
  /// Where the annotation is NOW, staged move included - not where it started.
  /// Reading rectPt would snap the outline back on every second drag.
  TextRect _effectiveRect(SavedAnnotation a, AnnotationEditSession session) =>
      session.moved[a.objectNumber] ?? a.rectPt;

  void _commit(SavedAnnotation target) {
    final live = _liveRect;
    setState(() {
      _liveRect = null;
      _activeHandle = null;
    });
    if (live == null) return;

    PdfPoint toPdf(Offset o) => canvasToPdf(
      o,
      pageRect: widget.pageRect,
      pageWidthPt: widget.pageWidthPt,
      pageHeightPt: widget.pageHeightPt,
    );

    final a = toPdf(live.topLeft);
    final b = toPdf(live.bottomRight);
    final rect = TextRect(
      left: a.x < b.x ? a.x : b.x,
      right: a.x > b.x ? a.x : b.x,
      bottom: a.y < b.y ? a.y : b.y,
      top: a.y > b.y ? a.y : b.y,
    );

    // An annotation dragged down to nothing cannot be selected again to undo
    // it, so refuse rather than let the user lose it.
    if (rect.right - rect.left < 8 || rect.top - rect.bottom < 8) return;

    ref.read(annotationEditProvider.notifier).moveSelected(rect);
  }
```
- the painter draws the outline at `_liveRect ?? effectiveRect`, plus four
  8-pixel corner handles when the selection is resizable.

Handles are drawn only for `resizable` annotations, which keeps them off a
20pt note icon they would completely cover.

- [ ] **Step 6: Pass moves through Save**

In `lib/features/viewer/viewer_screen.dart`, in `_saveAnnotationEdits`, add
`moved: session.moved,` to the `save(...)` call.

- [ ] **Step 7: Verify on the simulator**

```bash
flutter build ios --simulator --debug
xcrun simctl install DFC5606D-37F0-4176-A73D-B8214C7F820F build/ios/iphonesimulator/Runner.app
xcrun simctl launch DFC5606D-37F0-4176-A73D-B8214C7F820F dev.folio.app
```

Draw a rectangle, save, reopen, then in Edit annotations drag it somewhere else
and save. Reopen and confirm it stayed. Resize it by a corner and confirm the
shape follows. Move a stamp and confirm it moves despite being delete-only.
Confirm a highlight cannot be dragged. **Demo this on the simulator.**

Note: any `flutter test integration_test/...` run overwrites
`build/ios/iphonesimulator/Runner.app` with the test harness. Rebuild before
installing for manual testing or the app launches to a blank screen.

- [ ] **Step 8: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: drag to move and resize saved annotations

Handles are drawn only for resizable annotations, which keeps them off a 20pt
note icon they would completely cover. Ink and stamps lock their aspect ratio;
stretched handwriting and a squashed APPROVED both read as broken.

A rect dragged below 8pt is discarded: an annotation dragged to nothing cannot
be selected again to undo it."
```

---

### Task 4: End-to-end verification and documentation

**Files:**
- Create: `integration_test/move_resize_flow_test.dart`
- Modify: `integration_test/all_tests.dart`, `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`

- [ ] **Step 1: Write the end-to-end flows**

`integration_test/move_resize_flow_test.dart` carries
`@Timeout(Duration(minutes: 5))`, builds a real library, and asserts by
**rendering**:

1. a moved annotation draws in its new position — render before and after and
   require more than 200 pixels to differ;
2. **it no longer draws in its old position** — sample the columns the
   annotation originally covered and require them to match the unannotated
   page;
3. **restyling after a move keeps the new position** — move it, save, reload,
   restyle it, save again, then load and assert its `/Rect` still matches the
   moved position. This is the regression test for the stale-geometry trap and
   must fail if geometry is not transformed;
4. a stamp moves even though `restylable` is false;
5. a resized shape covers more columns than before;
6. the source document is byte-identical afterwards.

Register it in `integration_test/all_tests.dart`:
```dart
import 'move_resize_flow_test.dart' as move_resize_flow;
// ...
  group('move_resize_flow', move_resize_flow.main);
```

- [ ] **Step 2: Run on the iOS simulator**

```bash
flutter test integration_test/all_tests.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including every earlier suite.

Use the aggregate entrypoint, not the directory: `flutter test integration_test`
reinstalls and relaunches the app once per file.

- [ ] **Step 3: Confirm the stale-geometry test actually bites**

In `transformAnnotationDict`, delete the geometry-key loop so only `/Rect` is
rewritten, then re-run the flow file.

Expected: `restyling after a move keeps the new position` FAILS. Revert.

If it passes, the assertion is measuring nothing and must be strengthened
before this slice ships — two earlier slices shipped assertions that did
exactly that.

- [ ] **Step 4: Run on the Android emulator**

```bash
flutter emulators --launch pixel_api35
flutter test integration_test/all_tests.dart -d emulator-5554
```

Expected: all pass. No Android claim before this.

- [ ] **Step 5: Verify the architectural guards still hold**

```bash
grep -nE "^\s+Future<.*> (write|save|export|materialise)" lib/domain/engine/pdf_engine.dart
```

Expected: no matches.

- [ ] **Step 6: Update the documentation**

- `FEATURES.md` — an SP-3f table for moving and resizing, ✅ where verified and
  🟡 for Windows. State that markup cannot be moved and notes cannot be resized.
- `LIMITATIONS.md` — remove "nothing can be moved, resized or reshaped" from the
  SP-3c entry, replacing it with the narrower truth: individual ink points
  cannot be reshaped, markup cannot be moved, notes cannot be resized, and
  repeated moves accumulate up to 0.005pt of rounding each.
- `ARCHITECTURE.md` — the probe result that an appearance `/BBox` maps onto
  `/Rect`; why geometry is rewritten anyway; the stated exception to the
  verbatim rule; why the union is walked once.
- `TESTING.md` — refresh counts and the date.

- [ ] **Step 7: Full verification and push**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
git add -A && git commit -m "test: add end-to-end move and resize flows and update docs

Every flow reopens the output and requires the annotation to render in its new
position and not its old one. Restyling after a move is asserted to keep the
new position, which is the regression test for rewriting /Rect without its
geometry."
git push -u origin feature/sp3f-move-and-resize
gh pr create --base develop --title "SP-3f: moving and resizing annotations"
```

Confirm all four CI jobs pass, including `build-windows`.

---

## Definition of done

- [ ] Drag to move, corner handles to resize, inside Edit annotations
- [ ] Markup cannot be moved; notes cannot be resized
- [ ] Ink and stamps resize with aspect locked; shapes resize freely
- [ ] `/Rect` and geometry always agree after a move, proven by mutation
- [ ] Restyling after a move keeps the new position
- [ ] A moved-and-restyled annotation emits exactly one override
- [ ] Every SP-3a through SP-3e test still passes
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

**Next:** SP-3 is complete. The remaining object-layer work from SP-2b — encryption authoring, content-stream access, compression — is still unscoped and should each be judged on its own evidence.
