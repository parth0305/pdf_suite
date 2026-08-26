# SP-3c — Editing and Deleting Saved Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user delete any saved annotation, and restyle the colour and stroke width of any annotation whose geometry Folio can read back.

**Architecture:** A new `PdfObjectIndex` owns brace-balanced dictionary matching and the last-definition-wins rule, and both `PdfObjectReader` (page dictionaries only, unchanged API) and a new `PdfAnnotationReader` read through it. Edits are staged in an `AnnotationEditSession` and written as a single PDF incremental update: deletes drop a reference from an overridden page dictionary, restyles override the annotation's own object number with new `/C`, `/BS /W` and a fresh `/AP`, copying every geometry key verbatim.

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5, pdfrx 2.4.7 (PDFium), drift 2.34.3, flutter_riverpod 3.3.2.

**Spec:** `docs/superpowers/specs/2026-08-26-sp3c-annotation-editing-design.md`

## Global Constraints

- **Zero AI, zero paid or proprietary SDKs, no GPL/LGPL/AGPL dependencies.** No new dependencies at all in this slice.
- **Never destroy originals.** Imported documents produce a new document on save. Only Folio-created documents are rewritten.
- **`PdfEngine` has no write method and must not gain one.** There is a Definition-of-Done check.
- **`PdfObjectReader` handles page dictionaries and nothing else.** Its own doc comment says a caller needing more should trigger a scope rethink. That rethink produced `PdfObjectIndex` and `PdfAnnotationReader`; do not grow `PdfObjectReader`.
- **Never log document content, passwords, filenames or paths.**
- **Folio stamps no `/Producer`, no `/ModDate`, and no ownership marker** into documents or annotations.
- **A feature is not done until it has been verified by rendering.** Asserting bytes are present proves nothing: that is exactly how the PR #6 orphaning bug shipped.
- Run `dart format lib test integration_test scripts` and `flutter analyze --fatal-infos` before every commit.

## Critical context the implementer will not guess

**Storage is content-addressed.** `DocumentWriter.store` names the file `<sha256>.pdf`. Editing content therefore changes the file's path — "in place" means *the same library row*, not the same file path. Task 5 adds `replaceManagedContent`, which writes the new bytes, repoints the existing row, and deletes the old file **only when no other row references it** (two identical imports share one file).

**`pdfNumber` truncates to two decimals.** Regenerating a geometry key from parsed doubles would move an annotation by up to 0.005pt. Geometry keys are therefore copied out of the source dictionary as **raw substrings**. The `/AP` appearance stream is regenerated from parsed doubles, which is fine — an appearance is derived, and the error is far below a visible threshold.

**Restyling reuses existing appearance code.** `TextMarkup` and `DrawingAnnotation` both already take `colorArgb`, and `DrawingAnnotation` takes `strokeWidth`. Reconstruct the sealed `Annotation` from parsed geometry, then call the existing `appearanceStream`/`appearanceDict` or `drawingAppearanceStream`/`drawingAppearanceDict`. Write no new appearance code.

## File structure

| File | Responsibility |
|---|---|
| `lib/domain/annotations/pdf_object_index.dart` | **New.** Object number → latest raw body. Brace matching, last-definition-wins, xref-stream detection. |
| `lib/domain/annotations/pdf_object_reader.dart` | **Modify.** Same public API, now reading through the index. |
| `lib/domain/annotations/pdf_annotation_reader.dart` | **New.** `/Annots` refs → `SavedAnnotation`, including a reconstructed `Annotation` when restylable. |
| `lib/domain/annotations/pdf_annotation_editor.dart` | **New.** Applies deletes and restyles as one incremental update. |
| `lib/domain/annotations/annotation_edit_session.dart` | **New.** Staged deletes and restyles with undo. |
| `lib/data/local/app_database.dart` | **Modify.** Schema v3: `createdByFolio` column. |
| `lib/data/local/library_dao.dart` | **Modify.** `replaceContent`, `countByRelativePath`. |
| `lib/domain/repositories/library_repository.dart` | **Modify.** `replaceManagedContent`. |
| `lib/data/repositories/library_repository_impl.dart` | **Modify.** Implements it. |
| `lib/data/repositories/document_writer.dart` | **Modify.** Marks what it writes as Folio-created. |
| `lib/domain/repositories/annotation_edit_repository.dart` | **New.** Load, then save via in-place or new-document. |
| `lib/data/repositories/annotation_edit_repository_impl.dart` | **New.** Implements it. |
| `lib/features/viewer/annotation_edit_providers.dart` | **New.** Riverpod state for the mode. |
| `lib/features/viewer/widgets/annotation_selection_overlay.dart` | **New.** Tap hit-testing and the selection outline. |
| `lib/features/viewer/widgets/annotation_list_panel.dart` | **New.** One row per annotation on the page. |
| `lib/features/viewer/widgets/annotation_edit_toolbar.dart` | **New.** Colour, thickness, Delete, pinned Save. |
| `lib/features/viewer/viewer_screen.dart` | **Modify.** `_ViewerMode.annotations` and its wiring. |

---

# Stage 1 — Reading and writing edits

Ends with: deletes and restyles applied to real PDF bytes, proven by unit tests.

---

### Task 1: PdfObjectIndex

**Files:**
- Create: `lib/domain/annotations/pdf_object_index.dart`
- Modify: `lib/domain/annotations/pdf_object_reader.dart`
- Test: `test/domain/annotations/pdf_object_index_test.dart`

**Interfaces:**
- Produces: `PdfObjectIndex.parse(String)`, `String? bodyOf(int)`, `Iterable<int> get objectNumbers`, `bool get usesXrefStream`, and `static int matchingClose(String text, int openIndex)`

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/pdf_object_index_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';

void main() {
  test('indexes objects by number', () {
    final index = PdfObjectIndex.parse(
      '%PDF-1.4\n'
      '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
      '7 0 obj\n<< /Type /Annot /Subtype /Ink >>\nendobj\n',
    );

    expect(index.bodyOf(1), contains('/Catalog'));
    expect(index.bodyOf(7), contains('/Ink'));
    expect(index.bodyOf(99), isNull);
  });

  // Incremental updates append a NEW definition of an existing object. A
  // reader walking the trailer chain backwards sees the LAST one; reading the
  // superseded copy is what orphaned annotations before PR #6.
  test('the last definition of an object number wins', () {
    final index = PdfObjectIndex.parse(
      '3 0 obj\n<< /Type /Page >>\nendobj\n'
      '3 0 obj\n<< /Type /Page /Annots [7 0 R] >>\nendobj\n',
    );

    expect(index.bodyOf(3), contains('/Annots'));
  });

  test('object numbers are listed in first-appearance order', () {
    final index = PdfObjectIndex.parse(
      '5 0 obj\n<< >>\nendobj\n'
      '2 0 obj\n<< >>\nendobj\n'
      '5 0 obj\n<< /Again true >>\nendobj\n',
    );

    expect(index.objectNumbers, [5, 2]);
  });

  // A nested dictionary must not end the outer one early.
  test('nested dictionaries do not terminate the outer one', () {
    final index = PdfObjectIndex.parse(
      '4 0 obj\n<< /AP << /N 9 0 R >> /F 4 >>\nendobj\n',
    );

    expect(index.bodyOf(4), contains('/F 4'));
  });

  test('detects cross-reference streams', () {
    expect(
      PdfObjectIndex.parse('4 0 obj\n<< /Type /XRef >>\nendobj\n')
          .usesXrefStream,
      isTrue,
    );
    expect(
      PdfObjectIndex.parse('4 0 obj\n<< /Type /Page >>\nendobj\n')
          .usesXrefStream,
      isFalse,
    );
  });

  test('an object with no dictionary is skipped, not crashed on', () {
    final index = PdfObjectIndex.parse('9 0 obj\n[7 0 R]\nendobj\n');
    expect(index.bodyOf(9), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_object_index_test.dart`
Expected: FAIL — `Error when reading 'lib/domain/annotations/pdf_object_index.dart'`

- [ ] **Step 3: Implement the index**

`lib/domain/annotations/pdf_object_index.dart`:
```dart
/// Maps a PDF object number to its latest dictionary body.
///
/// This indexes `N 0 obj ... endobj` spans and stops. It resolves nothing,
/// types nothing, and reads no streams - it exists so that page and annotation
/// readers can share two mechanics that are genuinely general:
///
///  - dictionaries matched by brace balance, so a nested `<< >>` cannot end one
///    early;
///  - the LAST definition of an object number wins, which is what a reader
///    walking the trailer chain backwards sees. Reading a superseded
///    dictionary silently orphans everything the newer one references.
class PdfObjectIndex {
  PdfObjectIndex._(this._bodies, this._order, this.usesXrefStream);

  final Map<int, String> _bodies;
  final List<int> _order;

  /// True for PDF 1.5+ cross-reference streams, where the incremental-update
  /// technique does not hold.
  final bool usesXrefStream;

  static PdfObjectIndex parse(String pdfText) {
    final bodies = <int, String>{};
    final order = <int>[];

    for (final start in RegExp(r'(\d+)\s+0\s+obj').allMatches(pdfText)) {
      final open = pdfText.indexOf('<<', start.end);
      if (open < 0) continue;

      // `<<` must belong to THIS object, not a later one.
      final end = pdfText.indexOf('endobj', start.end);
      if (end >= 0 && open > end) continue;

      final close = matchingClose(pdfText, open);
      if (close < 0) continue;

      final number = int.parse(start.group(1)!);
      if (!bodies.containsKey(number)) order.add(number);
      bodies[number] = pdfText.substring(open, close + 2);
    }

    return PdfObjectIndex._(
      bodies,
      order,
      RegExp(r'/Type\s*/XRef').hasMatch(pdfText),
    );
  }

  /// The latest dictionary for [objectNumber], or null if there is none.
  String? bodyOf(int objectNumber) => _bodies[objectNumber];

  /// Object numbers in the order they first appear.
  Iterable<int> get objectNumbers => List.unmodifiable(_order);

  /// Index of the `>>` closing the `<<` at [openIndex], honouring nesting.
  static int matchingClose(String text, int openIndex) {
    var depth = 0;
    for (var i = openIndex; i < text.length - 1; i++) {
      if (text[i] == '<' && text[i + 1] == '<') {
        depth++;
        i++;
      } else if (text[i] == '>' && text[i + 1] == '>') {
        depth--;
        if (depth == 0) return i;
        i++;
      }
    }
    return -1;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_object_index_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 5: Refactor PdfObjectReader onto the index**

In `lib/domain/annotations/pdf_object_reader.dart`, replace the body of `parse` and delete the now-duplicated `_matchingClose`. The public API does not change.

```dart
  static PdfObjectReader parse(String pdfText) {
    final index = PdfObjectIndex.parse(pdfText);
    final pages = <PdfPageObject>[];

    for (final number in index.objectNumbers) {
      final dict = index.bodyOf(number)!;
      // /Type /Page but not /Pages: the next character must not be a letter.
      if (!RegExp(r'/Type\s*/Page(?![a-zA-Z])').hasMatch(dict)) continue;

      pages.add(
        PdfPageObject(
          objectNumber: number,
          rawDictionary: dict,
          existingAnnotRefs: _readAnnotRefs(dict),
        ),
      );
    }

    return PdfObjectReader._(pages, index.usesXrefStream);
  }
```

Add `import 'package:folio/domain/annotations/pdf_object_index.dart';` and remove the `static int _matchingClose(...)` method entirely.

- [ ] **Step 6: Run the whole suite — the refactor must change nothing**

Run: `flutter test`
Expected: all pass, including every SP-3a and SP-3b test and the PR #6 regression tests. The reader's behaviour is unchanged; those tests prove it.

- [ ] **Step 7: Mutation-test the shared rule**

In `pdf_object_index.dart`, change `bodies[number] = ...` to only assign when the key is absent (`bodies.putIfAbsent(number, () => ...)`), which restores first-definition-wins. Run `flutter test`.

Expected: `the last definition of an object number wins` FAILS, **and** the PR #6 regression test `the LAST definition of a page object wins` in `pdf_object_reader_test.dart` FAILS. Revert. Two independent suites guard this rule because getting it wrong destroys user data silently.

- [ ] **Step 8: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "refactor: extract PdfObjectIndex from PdfObjectReader

Brace-balanced dictionary matching and the last-definition-wins rule are needed
by any object lookup, not just page dictionaries. Extracting them lets the
annotation reader share them without growing PdfObjectReader past the page
dictionaries its own documentation limits it to."
```

---

### Task 2: PdfAnnotationReader

**Files:**
- Create: `lib/domain/annotations/pdf_annotation_reader.dart`
- Test: `test/domain/annotations/pdf_annotation_reader_test.dart`

**Interfaces:**
- Consumes: `PdfObjectIndex` (Task 1), `PdfObjectReader` (existing), `TextRect` from `pdf_types.dart`, `Annotation`/`TextMarkup`/`DrawingAnnotation`/`MarkupKind`/`DrawingKind` from `annotation.dart`
- Produces: `SavedAnnotation` with fields `objectNumber`, `pageIndex`, `subtype`, `rectPt`, `colorArgb`, `strokeWidth`, `rawDictionary`, `reconstructed`; getter `bool get restylable`; and `PdfAnnotationReader.parse(String)` with `List<SavedAnnotation> onPage(int)` and `List<SavedAnnotation> get all`

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/pdf_annotation_reader_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';

String docWith(String annots, String objects) =>
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
    '/Annots [$annots] >>\nendobj\n'
    '$objects'
    'trailer\n<< /Size 20 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

const highlight =
    '7 0 obj\n<< /Type /Annot /Subtype /Highlight /Rect [60 700 120 712] '
    '/QuadPoints [60 712 120 712 60 700 120 700] /C [1 1 0] /CA 1 /F 4 >>\n'
    'endobj\n';

const ink =
    '8 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [10 20 50 80] '
    '/InkList [[10 20 30 50 50 80]] /C [0 0 1] /CA 1 /F 4 '
    '/BS << /W 3 >> >>\nendobj\n';

const stamp =
    '9 0 obj\n<< /Type /Annot /Subtype /Stamp /Rect [0 0 10 10] >>\nendobj\n';

void main() {
  group('reading annotations back', () {
    test('finds every annotation referenced by the page', () {
      final found = PdfAnnotationReader.parse(
        docWith('7 0 R 8 0 R', '$highlight$ink'),
      ).onPage(0);

      expect(found.map((a) => a.subtype), ['Highlight', 'Ink']);
      expect(found.map((a) => a.objectNumber), [7, 8]);
    });

    test('reads /Rect into PDF space', () {
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', ink),
      ).onPage(0).single;

      expect(a.rectPt.left, 10);
      expect(a.rectPt.bottom, 20);
      expect(a.rectPt.right, 50);
      expect(a.rectPt.top, 80);
    });

    // /C holds components in 0..1, not bytes.
    test('converts /C to opaque ARGB', () {
      final a = PdfAnnotationReader.parse(
        docWith('7 0 R', highlight),
      ).onPage(0).single;

      expect(a.colorArgb, 0xFFFFFF00);
    });

    test('reads the stroke width from /BS /W', () {
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', ink),
      ).onPage(0).single;

      expect(a.strokeWidth, 3);
    });

    test('a missing /C and /BS read as null, not as a default', () {
      final a = PdfAnnotationReader.parse(
        docWith('9 0 R', stamp),
      ).onPage(0).single;

      expect(a.colorArgb, isNull);
      expect(a.strokeWidth, isNull);
    });
  });

  group('restylability', () {
    test('markup with /QuadPoints is restylable as a TextMarkup', () {
      final a = PdfAnnotationReader.parse(
        docWith('7 0 R', highlight),
      ).onPage(0).single;

      expect(a.restylable, isTrue);
      final markup = a.reconstructed! as TextMarkup;
      expect(markup.kind, MarkupKind.highlight);
      expect(markup.quads, hasLength(1));
      expect(markup.quads.single.left, 60);
      expect(markup.quads.single.top, 712);
    });

    test('ink with /InkList is restylable as a DrawingAnnotation', () {
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', ink),
      ).onPage(0).single;

      final drawing = a.reconstructed! as DrawingAnnotation;
      expect(drawing.kind, DrawingKind.ink);
      expect(drawing.points, hasLength(3));
      expect(drawing.points.first.x, 10);
      expect(drawing.points.first.y, 20);
    });

    test('a square is restylable from its /Rect alone', () {
      const square =
          '8 0 obj\n<< /Type /Annot /Subtype /Square /Rect [10 20 50 80] '
          '/C [0 0 1] >>\nendobj\n';
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', square),
      ).onPage(0).single;

      expect((a.reconstructed! as DrawingAnnotation).kind,
          DrawingKind.rectangle);
    });

    // We must not regenerate an appearance for a subtype we do not model:
    // that risks corrupting how another tool's annotation renders.
    test('an unmodelled subtype is delete-only', () {
      final a = PdfAnnotationReader.parse(
        docWith('9 0 R', stamp),
      ).onPage(0).single;

      expect(a.restylable, isFalse);
      expect(a.reconstructed, isNull);
    });

    test('a subtype we model but whose geometry is missing is delete-only', () {
      const brokenInk =
          '8 0 obj\n<< /Type /Annot /Subtype /Ink /Rect [10 20 50 80] >>\n'
          'endobj\n';
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', brokenInk),
      ).onPage(0).single;

      expect(a.restylable, isFalse);
    });
  });

  group('damaged documents', () {
    // A damaged document is not a reason to refuse the whole page.
    test('a dangling reference is skipped, not thrown on', () {
      final found = PdfAnnotationReader.parse(
        docWith('7 0 R 42 0 R', highlight),
      ).onPage(0);

      expect(found, hasLength(1));
      expect(found.single.objectNumber, 7);
    });

    test('all spans pages, including past an empty one', () {
      const twoPages =
          '%PDF-1.4\n'
          '2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>\nendobj\n'
          '3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] >>\nendobj\n'
          '4 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] '
          '/Annots [8 0 R] >>\nendobj\n'
          '$ink'
          'trailer\n<< /Size 20 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      final reader = PdfAnnotationReader.parse(twoPages);
      expect(reader.onPage(0), isEmpty);
      expect(reader.all.map((a) => a.objectNumber), [8]);
    });

    test('a page with no /Annots yields nothing', () {
      const plain =
          '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] >>\nendobj\n'
          'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

      expect(PdfAnnotationReader.parse(plain).onPage(0), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_annotation_reader_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement the reader**

`lib/domain/annotations/pdf_annotation_reader.dart`:
```dart
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// An annotation already present in a document.
class SavedAnnotation {
  const SavedAnnotation({
    required this.objectNumber,
    required this.pageIndex,
    required this.subtype,
    required this.rectPt,
    required this.rawDictionary,
    this.colorArgb,
    this.strokeWidth,
    this.reconstructed,
  });

  final int objectNumber;
  final int pageIndex;

  /// The subtype name without its leading slash, e.g. `Highlight`.
  final String subtype;

  final TextRect rectPt;

  /// The dictionary exactly as it appears in the file. Geometry is copied out
  /// of this verbatim, never re-emitted from parsed doubles.
  final String rawDictionary;

  final int? colorArgb;
  final double? strokeWidth;

  /// The annotation rebuilt as one of Folio's own types, when its geometry can
  /// be read. Null means Folio cannot regenerate an appearance for it.
  final Annotation? reconstructed;

  /// Colour and width can be changed only when an appearance can be rebuilt.
  bool get restylable => reconstructed != null;
}

/// Reads annotations already present in a document.
///
/// Deliberately narrow: it reads the five fields an edit needs and the
/// geometry key each modelled subtype implies. It resolves nothing else.
class PdfAnnotationReader {
  PdfAnnotationReader._(this._byPage);

  final Map<int, List<SavedAnnotation>> _byPage;

  static PdfAnnotationReader parse(String pdfText) {
    final index = PdfObjectIndex.parse(pdfText);
    final pages = PdfObjectReader.parse(pdfText);
    final byPage = <int, List<SavedAnnotation>>{};

    for (var pageIndex = 0; ; pageIndex++) {
      final page = pages.pageAt(pageIndex);
      if (page == null) break;

      final found = <SavedAnnotation>[];
      for (final ref in page.existingAnnotRefs) {
        final number = int.parse(ref.split(' ').first);
        final dict = index.bodyOf(number);
        // A dangling reference is a damaged document, not a reason to refuse
        // the whole page.
        if (dict == null) continue;

        final annotation = _read(number, pageIndex, dict);
        if (annotation != null) found.add(annotation);
      }
      byPage[pageIndex] = found;
    }

    return PdfAnnotationReader._(byPage);
  }

  List<SavedAnnotation> onPage(int pageIndex) =>
      List.unmodifiable(_byPage[pageIndex] ?? const []);

  /// Every annotation in the document, in page then reference order.
  ///
  /// Callers must not iterate pages until one comes back empty: a document
  /// with annotations only on page 3 would stop at page 1.
  List<SavedAnnotation> get all => List.unmodifiable([
    for (final page in _byPage.keys.toList()..sort()) ..._byPage[page]!,
  ]);

  static SavedAnnotation? _read(int number, int pageIndex, String dict) {
    final subtype = RegExp(r'/Subtype\s*/(\w+)').firstMatch(dict)?.group(1);
    final rect = _numbersIn(dict, 'Rect');
    if (subtype == null || rect.length < 4) return null;

    final rectPt = TextRect(
      left: rect[0],
      bottom: rect[1],
      right: rect[2],
      top: rect[3],
    );
    final colour = _colourOf(dict);
    final width = _widthOf(dict);

    return SavedAnnotation(
      objectNumber: number,
      pageIndex: pageIndex,
      subtype: subtype,
      rectPt: rectPt,
      rawDictionary: dict,
      colorArgb: colour,
      strokeWidth: width,
      reconstructed: _reconstruct(
        subtype: subtype,
        pageIndex: pageIndex,
        dict: dict,
        rectPt: rectPt,
        colorArgb: colour ?? 0xFF000000,
        strokeWidth: width ?? 2,
      ),
    );
  }

  /// Rebuilds one of Folio's own annotation types from the geometry key the
  /// subtype implies, or returns null when that geometry is absent.
  static Annotation? _reconstruct({
    required String subtype,
    required int pageIndex,
    required String dict,
    required TextRect rectPt,
    required int colorArgb,
    required double strokeWidth,
  }) {
    final markupKind = switch (subtype) {
      'Highlight' => MarkupKind.highlight,
      'Underline' => MarkupKind.underline,
      'StrikeOut' => MarkupKind.strikeOut,
      _ => null,
    };

    if (markupKind != null) {
      final quads = _numbersIn(dict, 'QuadPoints');
      if (quads.length < 8) return null;
      return TextMarkup(
        kind: markupKind,
        pageIndex: pageIndex,
        quads: [
          // Eight numbers per quad: upper-left, upper-right, lower-left,
          // lower-right (ISO 32000-1 Table 179).
          for (var i = 0; i + 7 < quads.length; i += 8)
            TextRect(
              left: quads[i],
              top: quads[i + 1],
              right: quads[i + 2],
              bottom: quads[i + 5],
            ),
        ],
        colorArgb: colorArgb,
      );
    }

    List<PdfPoint>? points;
    DrawingKind? kind;

    switch (subtype) {
      case 'Ink':
        final flat = _numbersIn(dict, 'InkList');
        if (flat.length < 4) return null;
        kind = DrawingKind.ink;
        points = [
          for (var i = 0; i + 1 < flat.length; i += 2)
            PdfPoint(flat[i], flat[i + 1]),
        ];
      case 'Square':
        kind = DrawingKind.rectangle;
        points = [
          PdfPoint(rectPt.left, rectPt.bottom),
          PdfPoint(rectPt.right, rectPt.top),
        ];
      case 'Circle':
        kind = DrawingKind.ellipse;
        points = [
          PdfPoint(rectPt.left, rectPt.bottom),
          PdfPoint(rectPt.right, rectPt.top),
        ];
      case 'Line':
        final l = _numbersIn(dict, 'L');
        if (l.length < 4) return null;
        // /LE marks an arrow; without it, a plain line.
        kind = dict.contains('/LE') ? DrawingKind.arrow : DrawingKind.line;
        points = [PdfPoint(l[0], l[1]), PdfPoint(l[2], l[3])];
      default:
        return null;
    }

    return DrawingAnnotation(
      kind: kind,
      pageIndex: pageIndex,
      points: points,
      colorArgb: colorArgb,
      strokeWidth: strokeWidth,
    );
  }

  /// Every number inside the bracketed value of [key], nesting flattened.
  static List<double> _numbersIn(String dict, String key) {
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

    return RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(dict.substring(start, end))
        .map((m) => double.parse(m.group(0)!))
        .toList();
  }

  /// `/C [r g b]` holds components in 0..1, not bytes.
  static int? _colourOf(String dict) {
    final c = _numbersIn(dict, 'C');
    if (c.length < 3) return null;
    int channel(double v) => (v.clamp(0, 1) * 255).round();
    return (0xFF << 24) |
        (channel(c[0]) << 16) |
        (channel(c[1]) << 8) |
        channel(c[2]);
  }

  static double? _widthOf(String dict) {
    final match = RegExp(
      r'/BS\s*<<[^>]*?/W\s+(-?\d+(?:\.\d+)?)',
    ).firstMatch(dict);
    return match == null ? null : double.parse(match.group(1)!);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_annotation_reader_test.dart`
Expected: PASS — 13 tests

- [ ] **Step 5: Mutation-test the delete-only boundary**

In `_reconstruct`, change the `default: return null;` case to `default: kind = DrawingKind.rectangle; points = [PdfPoint(rectPt.left, rectPt.bottom), PdfPoint(rectPt.right, rectPt.top)];`. Run the test file.

Expected: `an unmodelled subtype is delete-only` FAILS. Revert. This mutation is what "we'll just treat unknown annotations as rectangles" looks like in code, and it would silently replace a third-party stamp's appearance with a box.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: read saved annotations back out of a document

Reads the five fields an edit needs and rebuilds Folio's own annotation types
from the geometry key each modelled subtype implies. An annotation whose
geometry cannot be read is delete-only rather than restylable: regenerating an
appearance for a subtype we do not model would corrupt how another tool's
annotation renders.

A dangling reference is skipped. A damaged document is not a reason to refuse
every annotation on the page."
```

---

### Task 3: The annotation editor

**Files:**
- Create: `lib/domain/annotations/pdf_annotation_editor.dart`
- Test: `test/domain/annotations/pdf_annotation_editor_test.dart`

**Interfaces:**
- Consumes: `SavedAnnotation`, `PdfAnnotationReader` (Task 2), `PdfObjectReader`, `appearanceStream`/`appearanceDict` from `pdf_appearance.dart`, `drawingAppearanceStream`/`drawingAppearanceDict` from `drawing_appearance.dart`
- Produces: `class AnnotationStyle { const AnnotationStyle({required int colorArgb, required double strokeWidth}); }` and `Uint8List applyAnnotationEdits(Uint8List pdf, {required Set<int> deleted, required Map<int, AnnotationStyle> restyled})`

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/pdf_annotation_editor_test.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';

Uint8List annotated() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
    '/Annots [7 0 R 8 0 R] >>\nendobj\n'
    '7 0 obj\n<< /Type /Annot /Subtype /Highlight /Rect [60 700 120 712] '
    '/QuadPoints [60.125 712.5 120 712.5 60.125 700 120 700] /C [1 1 0] '
    '/CA 1 /F 4 /AP << /N 6 0 R >> >>\nendobj\n'
    '8 0 obj\n<< /Type /Annot /Subtype /Square /Rect [10 20 50 80] '
    '/C [0 0 1] /CA 1 /F 4 /BS << /W 3 >> /AP << /N 5 0 R >> >>\nendobj\n'
    'xref\n0 9\n0000000000 65535 f \n'
    'trailer\n<< /Size 9 /Root 1 0 R >>\n'
    'startxref\n9\n%%EOF\n',
  ),
);

void main() {
  group('deleting', () {
    test('drops the reference from an overridden page dictionary', () {
      final text = latin1.decode(
        applyAnnotationEdits(annotated(), deleted: {7}, restyled: const {}),
      );

      // The final page override must reference only the survivor.
      final overrides = RegExp(
        r'3 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).toList();
      expect(overrides, hasLength(2), reason: 'original plus one override');
      expect(overrides.last.group(1), contains('8 0 R'));
      expect(overrides.last.group(1), isNot(contains('7 0 R')));
    });

    test('the original bytes are still present, untouched', () {
      final original = annotated();
      final out = applyAnnotationEdits(
        original,
        deleted: {7},
        restyled: const {},
      );

      expect(out.sublist(0, original.length), original);
    });

    test('deleting every annotation leaves an empty /Annots', () {
      final text = latin1.decode(
        applyAnnotationEdits(annotated(), deleted: {7, 8}, restyled: const {}),
      );
      expect(text, contains('/Annots []'));
    });
  });

  group('restyling', () {
    test('overrides the SAME object number', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            8: const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 6),
          },
        ),
      );

      expect(RegExp(r'8 0 obj').allMatches(text).length, 2);
    });

    test('writes the new colour and width', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            8: const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 6),
          },
        ),
      );

      final override = RegExp(
        r'8 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      expect(override, contains('/C [1 0 0]'));
      expect(override, contains('/W 6'));
    });

    // pdfNumber truncates to two decimals, so re-emitting geometry from
    // parsed doubles would move the annotation. It must be copied verbatim.
    test('geometry is copied verbatim, at full precision', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            7: const AnnotationStyle(colorArgb: 0xFF00FF00, strokeWidth: 2),
          },
        ),
      );

      final override = RegExp(
        r'7 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      expect(
        override,
        contains('/QuadPoints [60.125 712.5 120 712.5 60.125 700 120 700]'),
        reason: 'a restyle must not move the annotation by a rounding error',
      );
    });

    test('a fresh appearance stream is emitted and referenced', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            8: const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 6),
          },
        ),
      );

      final override = RegExp(
        r'8 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      // Not the original /AP object.
      expect(override, isNot(contains('/N 5 0 R')));
      expect(override, contains('/AP'));
      expect(text, contains('/Subtype /Form'));
    });

    test('a restyled annotation keeps its place in /Annots', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          annotated(),
          deleted: const {},
          restyled: {
            8: const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 6),
          },
        ),
      );

      // Restyling overrides an object; it must not rewrite the page at all.
      expect(RegExp(r'3 0 obj').allMatches(text).length, 1);
    });
  });

  group('refusals', () {
    test('nothing staged returns the input unchanged', () {
      final original = annotated();
      expect(
        applyAnnotationEdits(original, deleted: const {}, restyled: const {}),
        original,
      );
    });

    test('a cross-reference-stream document is refused', () {
      final modern = Uint8List.fromList(
        latin1.encode(
          '%PDF-1.5\n'
          '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
          '4 0 obj\n<< /Type /XRef /Size 5 >>\nstream\n\nendstream\nendobj\n'
          'startxref\n9\n%%EOF\n',
        ),
      );

      expect(
        () => applyAnnotationEdits(modern, deleted: {7}, restyled: const {}),
        throwsA(isA<UnsupportedPdfStructure>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_annotation_editor_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement the editor**

`lib/domain/annotations/pdf_annotation_editor.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/drawing_appearance.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';

/// The only properties a restyle may change.
class AnnotationStyle {
  const AnnotationStyle({required this.colorArgb, required this.strokeWidth});

  final int colorArgb;
  final double strokeWidth;
}

/// Applies deletions and restyles as one PDF incremental update.
///
/// The original bytes are never rewritten. Deleting drops a reference from an
/// overridden page dictionary, which leaves the annotation object in the file
/// but unreferenced, so it stops rendering. Restyling overrides the
/// annotation's own object number.
///
/// Geometry keys are copied out of the source dictionary as raw substrings.
/// Re-emitting them from parsed doubles would round to two decimals and move
/// the annotation - a corruption invisible until someone compared renders.
Uint8List applyAnnotationEdits(
  Uint8List pdf, {
  required Set<int> deleted,
  required Map<int, AnnotationStyle> restyled,
}) {
  if (deleted.isEmpty && restyled.isEmpty) return pdf;

  final text = latin1.decode(pdf, allowInvalid: true);
  final pages = PdfObjectReader.parse(text);

  if (pages.usesXrefStream) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'PDF 1.5+ cross-reference stream',
    );
  }

  final startxref = RegExp(
    r'startxref\s+(\d+)\s*%%EOF\s*$',
  ).firstMatch(text.trimRight());
  final roots = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  final sizes = RegExp(r'/Size\s+(\d+)').allMatches(text);

  if (startxref == null || roots.isEmpty || sizes.isEmpty) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'no classic trailer with /Root, /Size and startxref',
    );
  }

  final saved = PdfAnnotationReader.parse(text);
  final prevOffset = int.parse(startxref.group(1)!);
  final root = roots.last;
  var nextObj = int.parse(sizes.last.group(1)!);

  final out = <int>[...pdf];
  if (out.isNotEmpty && out.last != 0x0a) out.add(0x0a);

  final offsets = <int, int>{};
  void emit(int number, String body) {
    offsets[number] = out.length;
    out.addAll(latin1.encode('$number 0 obj\n$body\nendobj\n'));
  }

  // Restyle: override the annotation's own object, with a fresh appearance.
  for (final entry in restyled.entries) {
    final target = _find(saved, entry.key);
    if (target?.reconstructed == null) continue;

    final restyledAnnotation = _withStyle(
      target!.reconstructed!,
      entry.value,
    );

    final (stream, dict) = switch (restyledAnnotation) {
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
    };

    final apNum = nextObj++;
    emit(apNum, '$dict\nstream\n${stream}endstream');
    emit(
      target.objectNumber,
      _restyledDictionary(target.rawDictionary, entry.value, apNum),
    );
  }

  // Delete: override each affected page with the surviving references.
  if (deleted.isNotEmpty) {
    for (var pageIndex = 0; ; pageIndex++) {
      final page = pages.pageAt(pageIndex);
      if (page == null) break;

      final survivors = page.existingAnnotRefs
          .where((ref) => !deleted.contains(int.parse(ref.split(' ').first)))
          .toList();
      if (survivors.length == page.existingAnnotRefs.length) continue;

      emit(
        page.objectNumber,
        page.rawDictionary.replaceFirst(
          RegExp(r'/Annots\s*\[[^\]]*\]'),
          '/Annots [${survivors.join(' ')}]',
        ),
      );
    }
  }

  if (offsets.isEmpty) return pdf;

  // One xref subsection per object: always valid, and avoids having to detect
  // runs of consecutive numbers.
  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  for (final n in offsets.keys.toList()..sort()) {
    buffer.writeln('$n 1');
    buffer.writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');
  buffer.writeln(
    '<< /Size $nextObj /Root ${root.group(1)} ${root.group(2)} R '
    '/Prev $prevOffset >>',
  );
  buffer.writeln('startxref');
  buffer.writeln('$xrefOffset');
  buffer.write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}

SavedAnnotation? _find(PdfAnnotationReader reader, int objectNumber) {
  for (final a in reader.all) {
    if (a.objectNumber == objectNumber) return a;
  }
  return null;
}

Annotation _withStyle(Annotation annotation, AnnotationStyle style) =>
    switch (annotation) {
      TextMarkup() => TextMarkup(
        kind: annotation.kind,
        pageIndex: annotation.pageIndex,
        quads: annotation.quads,
        colorArgb: style.colorArgb,
      ),
      DrawingAnnotation() => DrawingAnnotation(
        kind: annotation.kind,
        pageIndex: annotation.pageIndex,
        points: annotation.points,
        colorArgb: style.colorArgb,
        strokeWidth: style.strokeWidth,
      ),
    };

/// Rewrites only `/C`, `/BS` and `/AP`, leaving every other key - including
/// all geometry - exactly as it was in the source dictionary.
String _restyledDictionary(String source, AnnotationStyle style, int apNum) {
  String colour(int shift) =>
      pdfNumber(((style.colorArgb >> shift) & 0xFF) / 255);
  final c = '/C [${colour(16)} ${colour(8)} ${colour(0)}]';
  final bs = '/BS << /W ${pdfNumber(style.strokeWidth)} >>';
  final ap = '/AP << /N $apNum 0 R >>';

  var body = source.substring(2, source.length - 2).trim();
  body = body.replaceAll(RegExp(r'/C\s*\[[^\]]*\]'), '');
  body = body.replaceAll(RegExp(r'/BS\s*<<[^>]*>>'), '');
  body = body.replaceAll(RegExp(r'/AP\s*<<[^>]*>>'), '');
  body = body.replaceAll(RegExp(r'\s+'), ' ').trim();

  return '<< $body $c $bs $ap >>';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_annotation_editor_test.dart`
Expected: PASS — 10 tests

- [ ] **Step 5: Mutation-test the verbatim-geometry invariant**

In `_restyledDictionary`, additionally strip and re-emit the quad points by adding this before the return:

```dart
  body = body.replaceAll(RegExp(r'/QuadPoints\s*\[[^\]]*\]'), '/QuadPoints [60.13 712.5 120 712.5 60.13 700 120 700]');
```

Run the test file.

Expected: `geometry is copied verbatim, at full precision` FAILS, showing `60.13` where `60.125` belongs. Revert. This is precisely what re-emitting geometry through `pdfNumber` would do, and the drift is invisible in every other assertion.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: apply annotation deletes and restyles as an incremental update

Deleting drops a reference from an overridden page dictionary; the annotation
object stays in the file, unreferenced, and stops rendering. Restyling
overrides the annotation's own object number with a new colour, width and
appearance stream.

Geometry is copied out of the source dictionary as raw substrings. Re-emitting
it through pdfNumber would round to two decimals and move the annotation - a
corruption that no other assertion would have caught."
```

---

### Task 4: AnnotationEditSession

**Files:**
- Create: `lib/domain/annotations/annotation_edit_session.dart`
- Test: `test/domain/annotations/annotation_edit_session_test.dart`

**Interfaces:**
- Consumes: `SavedAnnotation` (Task 2), `AnnotationStyle` (Task 3)
- Produces: `AnnotationEditSession(List<SavedAnnotation> loaded)` with `List<SavedAnnotation> get annotations`, `List<SavedAnnotation> onPage(int)`, `void delete(int objectNumber)`, `void restyle(int objectNumber, AnnotationStyle)`, `Set<int> get deleted`, `Map<int, AnnotationStyle> get restyled`, `bool get isDirty`, `bool get canUndo`, `void undo()`, `AnnotationStyle? styleOf(int)`

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/annotation_edit_session_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation_edit_session.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';

SavedAnnotation saved(int number, {int page = 0}) => SavedAnnotation(
  objectNumber: number,
  pageIndex: page,
  subtype: 'Square',
  rectPt: const TextRect(left: 0, bottom: 0, right: 10, top: 10),
  rawDictionary: '<< /Subtype /Square >>',
);

const red = AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 4);
const blue = AnnotationStyle(colorArgb: 0xFF0000FF, strokeWidth: 2);

void main() {
  test('starts clean', () {
    final s = AnnotationEditSession([saved(7)]);

    expect(s.isDirty, isFalse);
    expect(s.canUndo, isFalse);
    expect(s.deleted, isEmpty);
    expect(s.restyled, isEmpty);
  });

  test('deleting stages an object number', () {
    final s = AnnotationEditSession([saved(7), saved(8)])..delete(7);

    expect(s.deleted, {7});
    expect(s.isDirty, isTrue);
  });

  // A deleted annotation must disappear from the list immediately, or the
  // user cannot tell the delete registered.
  test('a deleted annotation leaves the visible list', () {
    final s = AnnotationEditSession([saved(7), saved(8)])..delete(7);

    expect(s.annotations.map((a) => a.objectNumber), [8]);
  });

  test('restyling stages a style', () {
    final s = AnnotationEditSession([saved(7)])..restyle(7, red);

    expect(s.restyled[7], red);
    expect(s.styleOf(7), red);
  });

  test('restyling twice keeps only the latest style', () {
    final s = AnnotationEditSession([saved(7)])
      ..restyle(7, red)
      ..restyle(7, blue);

    expect(s.restyled[7], blue);
    expect(s.restyled, hasLength(1));
  });

  // Restyling something then deleting it must not leave a restyle staged for
  // an object that will no longer be referenced.
  test('deleting a restyled annotation drops its staged style', () {
    final s = AnnotationEditSession([saved(7)])
      ..restyle(7, red)
      ..delete(7);

    expect(s.restyled, isEmpty);
    expect(s.deleted, {7});
  });

  test('onPage filters by page', () {
    final s = AnnotationEditSession([saved(7), saved(8, page: 2)]);

    expect(s.onPage(0).map((a) => a.objectNumber), [7]);
    expect(s.onPage(2).map((a) => a.objectNumber), [8]);
  });

  test('undo reverses a delete', () {
    final s = AnnotationEditSession([saved(7)])..delete(7);
    s.undo();

    expect(s.deleted, isEmpty);
    expect(s.annotations, hasLength(1));
    expect(s.isDirty, isFalse);
  });

  test('undo reverses a restyle', () {
    final s = AnnotationEditSession([saved(7)])..restyle(7, red);
    s.undo();

    expect(s.restyled, isEmpty);
  });

  test('undo crosses operation types in order', () {
    final s = AnnotationEditSession([saved(7), saved(8)])
      ..restyle(7, red)
      ..delete(8);

    s.undo();
    expect(s.deleted, isEmpty);
    expect(s.restyled[7], red);

    s.undo();
    expect(s.restyled, isEmpty);
    expect(s.isDirty, isFalse);
  });

  test('undo on a clean session does nothing', () {
    final s = AnnotationEditSession([saved(7)])..undo();
    expect(s.isDirty, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/annotation_edit_session_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement the session**

`lib/domain/annotations/annotation_edit_session.dart`:
```dart
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';

/// Edits staged against annotations already saved in a document.
///
/// Nothing touches the file until the caller saves, so undo is a stack of
/// in-memory snapshots and an abandoned session leaves the document untouched.
/// The same shape as AnnotationSession and PageEditSession, deliberately.
class AnnotationEditSession {
  AnnotationEditSession(List<SavedAnnotation> loaded)
    : _loaded = List.unmodifiable(loaded);

  final List<SavedAnnotation> _loaded;

  Set<int> _deleted = {};
  Map<int, AnnotationStyle> _restyled = {};
  final List<({Set<int> deleted, Map<int, AnnotationStyle> restyled})> _undo =
      [];

  /// Everything still present, in load order. A deleted annotation leaves this
  /// list immediately, so the UI reflects the staged state.
  List<SavedAnnotation> get annotations => List.unmodifiable(
    _loaded.where((a) => !_deleted.contains(a.objectNumber)),
  );

  List<SavedAnnotation> onPage(int pageIndex) => List.unmodifiable(
    annotations.where((a) => a.pageIndex == pageIndex),
  );

  Set<int> get deleted => Set.unmodifiable(_deleted);
  Map<int, AnnotationStyle> get restyled => Map.unmodifiable(_restyled);

  AnnotationStyle? styleOf(int objectNumber) => _restyled[objectNumber];

  bool get isDirty => _deleted.isNotEmpty || _restyled.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;

  void _snapshot() {
    _undo.add((deleted: Set.of(_deleted), restyled: Map.of(_restyled)));
  }

  void delete(int objectNumber) {
    _snapshot();
    _deleted = {..._deleted, objectNumber};
    // A style staged for something about to be unreferenced is dead weight,
    // and would emit an override for an annotation nothing points at.
    _restyled = {..._restyled}..remove(objectNumber);
  }

  void restyle(int objectNumber, AnnotationStyle style) {
    _snapshot();
    _restyled = {..._restyled, objectNumber: style};
  }

  void undo() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    _deleted = previous.deleted;
    _restyled = previous.restyled;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/annotation_edit_session_test.dart`
Expected: PASS — 11 tests

- [ ] **Step 5: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: stage annotation deletes and restyles with undo

Deleting an annotation drops any style staged for it: an override emitted for
an object nothing references any more is dead weight in the file."
```

---

# Stage 2 — Persistence and the save model

Ends with: edits saved either in place or as a new document, chosen by provenance.

---

### Task 5: createdByFolio and in-place replacement

**Files:**
- Modify: `lib/data/local/app_database.dart`, `lib/data/local/library_dao.dart`, `lib/domain/models/library_document.dart`, `lib/domain/repositories/library_repository.dart`, `lib/data/repositories/library_repository_impl.dart`, `lib/data/repositories/document_writer.dart`
- Test: `test/data/repositories/library_replace_content_test.dart`

**Interfaces:**
- Produces: `LibraryDocument.createdByFolio` (bool); `LibraryRepository.replaceManagedContent({required int documentId, required Uint8List bytes})` returning `Future<LibraryDocument>`; `LibraryRepository.registerManaged(..., bool createdByFolio = false)`; DAO `replaceContent({required int id, required String refPayload, required int sizeBytes})` and `countByRefPayload(String)`

- [ ] **Step 1: Write the failing test**

`test/data/repositories/library_replace_content_test.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late DocumentWriter writer;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('replace');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    writer = DocumentWriter(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

  test('a document Folio writes is marked as Folio-created', () async {
    final doc = await writer.store(bytes('%PDF-1.4 one'), 'One.pdf');
    expect(doc.createdByFolio, isTrue);
  });

  test('an imported document is not marked as Folio-created', () async {
    final f = File('${root.path}/outside.pdf')
      ..writeAsBytesSync(bytes('%PDF-1.4 outside'));
    final doc = await library.importFile(f.path, displayName: 'Outside.pdf');

    expect(doc.createdByFolio, isFalse);
  });

  test('replacing content keeps the same library row', () async {
    final doc = await writer.store(bytes('%PDF-1.4 one'), 'One.pdf');

    final updated = await library.replaceManagedContent(
      documentId: doc.id,
      bytes: bytes('%PDF-1.4 one edited'),
    );

    expect(updated.id, doc.id);
    expect(updated.displayName, 'One.pdf');
    expect(await library.all(), hasLength(1));
  });

  test('replacing content writes the new bytes', () async {
    final doc = await writer.store(bytes('%PDF-1.4 one'), 'One.pdf');

    final updated = await library.replaceManagedContent(
      documentId: doc.id,
      bytes: bytes('%PDF-1.4 one edited'),
    );

    final onDisk = await File(
      await library.resolveReadablePath(updated),
    ).readAsString();
    expect(onDisk, '%PDF-1.4 one edited');
  });

  // Storage is content-addressed, so new bytes live at a new path. The old
  // file must not be left behind.
  test('the superseded file is removed', () async {
    final doc = await writer.store(bytes('%PDF-1.4 one'), 'One.pdf');
    final oldPath = await library.resolveReadablePath(doc);

    await library.replaceManagedContent(
      documentId: doc.id,
      bytes: bytes('%PDF-1.4 one edited'),
    );

    expect(File(oldPath).existsSync(), isFalse);
  });

  // Content-addressed storage means two identical documents share one file.
  // Removing it on behalf of one would break the other.
  test('a file another row still references is kept', () async {
    final first = await writer.store(bytes('%PDF-1.4 same'), 'First.pdf');
    final second = await writer.store(bytes('%PDF-1.4 same'), 'Second.pdf');
    expect(
      await library.resolveReadablePath(first),
      await library.resolveReadablePath(second),
      reason: 'identical content is stored once',
    );
    final shared = await library.resolveReadablePath(second);

    await library.replaceManagedContent(
      documentId: first.id,
      bytes: bytes('%PDF-1.4 changed'),
    );

    expect(File(shared).existsSync(), isTrue);
    expect(
      await File(await library.resolveReadablePath(second)).readAsString(),
      '%PDF-1.4 same',
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/repositories/library_replace_content_test.dart`
Expected: FAIL — `createdByFolio` and `replaceManagedContent` are not defined

- [ ] **Step 3: Add the column and bump the schema**

In `lib/data/local/app_database.dart`, add to `class Documents`:
```dart
  /// True when Folio itself produced this file, which makes it safe to rewrite
  /// in place. Imported copies are never rewritten.
  BoolColumn get createdByFolio => boolean().withDefault(const Constant(false))();
```

Change `int get schemaVersion => 2;` to `3`, and extend the migration:
```dart
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(collections);
        await m.addColumn(documents, documents.collectionId);
      }
      if (from < 3) {
        // Existing rows default to false, so documents created before this
        // column existed are treated as imported and produce a new document
        // on save. That is the safe direction.
        await m.addColumn(documents, documents.createdByFolio);
      }
    },
```

Run `dart run build_runner build --delete-conflicting-outputs` to regenerate `app_database.g.dart`.

- [ ] **Step 4: Carry the flag through the model and DAO**

In `lib/domain/models/library_document.dart`, add `required this.createdByFolio,` to the constructor, `final bool createdByFolio;` as a field, and `createdByFolio: createdByFolio,` to `copyWith`'s returned object.

In `lib/data/local/library_dao.dart`, add `createdByFolio` to `insertDocument`'s parameters and its inserted companion, map it in the row-to-model conversion, and add:
```dart
  Future<void> replaceContent({
    required int id,
    required String refPayload,
    required int sizeBytes,
  }) async {
    await (_db.update(_db.documents)..where((t) => t.id.equals(id))).write(
      DocumentsCompanion(
        refPayload: Value(refPayload),
        sizeBytes: Value(sizeBytes),
      ),
    );
  }

  Future<int> countByRefPayload(String refPayload) async {
    final rows = await (_db.select(
      _db.documents,
    )..where((t) => t.refPayload.equals(refPayload))).get();
    return rows.length;
  }
```

- [ ] **Step 5: Implement replaceManagedContent**

In `lib/domain/repositories/library_repository.dart`, add `bool createdByFolio` (defaulting to `false`) to `registerManaged`, and declare:
```dart
  /// Rewrites a managed document's content, keeping its library row.
  ///
  /// Storage is content-addressed, so new bytes live at a new path: this
  /// writes the new file, repoints the row, and removes the old file only when
  /// no other row still references it.
  Future<LibraryDocument> replaceManagedContent({
    required int documentId,
    required Uint8List bytes,
  });
```

In `lib/data/repositories/library_repository_impl.dart`:
```dart
  @override
  Future<LibraryDocument> replaceManagedContent({
    required int documentId,
    required Uint8List bytes,
  }) async {
    final doc = (await all()).firstWhere((d) => d.id == documentId);
    if (doc.ref is! ManagedRef) {
      throw StateError('only a managed document can be rewritten');
    }
    final oldRef = doc.ref as ManagedRef;

    final hash = sha256.convert(bytes).toString();
    final relative = p.join(hash.substring(0, 2), '$hash.pdf');

    await _writer.write(
      destination: File(p.join(_root.path, relative)),
      produce: (working) => working.writeAsBytes(bytes, flush: true),
      validate: (working) async => await working.length() == bytes.length,
    );

    final newRef = ManagedRef(relativePath: relative, contentHash: hash);
    await _dao.replaceContent(
      id: documentId,
      refPayload: newRef.encode(),
      sizeBytes: bytes.length,
    );

    // Identical content is stored once, so another row may still need the old
    // file. Removing it on their behalf would break them.
    if (oldRef.relativePath != relative &&
        await _dao.countByRefPayload(oldRef.encode()) == 0) {
      final old = File(p.join(_root.path, oldRef.relativePath));
      if (old.existsSync()) await old.delete();
    }

    return (await all()).firstWhere((d) => d.id == documentId);
  }
```

In `lib/data/repositories/document_writer.dart`, pass `createdByFolio: true` to `registerManaged`, and update `registerManaged`'s implementation to persist the flag.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/data/repositories/library_replace_content_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 7: Run the whole suite — the migration must not break existing rows**

Run: `flutter test`
Expected: all pass, including every library and page-operations test.

- [ ] **Step 8: Mutation-test the shared-file guard**

In `replaceManagedContent`, remove the `await _dao.countByRefPayload(oldRef.encode()) == 0` condition so the old file is always deleted. Run the test file.

Expected: `a file another row still references is kept` FAILS, and reading the second document throws. Revert. Content-addressed deduplication makes this a live hazard, not a theoretical one.

- [ ] **Step 9: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: record document provenance and support in-place replacement

Storage is content-addressed, so editing a document's bytes changes its path.
Rewriting in place therefore means keeping the library row and repointing it,
not overwriting a file.

The superseded file is removed only when no other row references it: identical
content is stored once, so deleting it on one document's behalf would break
every other document sharing it."
```

---

### Task 6: AnnotationEditRepository

**Files:**
- Create: `lib/domain/repositories/annotation_edit_repository.dart`, `lib/data/repositories/annotation_edit_repository_impl.dart`
- Test: `test/data/repositories/annotation_edit_repository_test.dart`

**Interfaces:**
- Consumes: `PdfAnnotationReader`, `applyAnnotationEdits`, `AnnotationStyle`, `LibraryRepository.replaceManagedContent`, `DocumentWriter.store`, `PdfMetadata`
- Produces: `AnnotationEditRepository` with `Future<List<SavedAnnotation>> load(int documentId)` and `Future<LibraryDocument> save({required int documentId, required Set<int> deleted, required Map<int, AnnotationStyle> restyled})`

- [ ] **Step 1: Write the failing test**

`test/data/repositories/annotation_edit_repository_test.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_edit_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';

const annotatedPdf =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
    '/Annots [7 0 R 8 0 R] >>\nendobj\n'
    '7 0 obj\n<< /Type /Annot /Subtype /Square /Rect [10 20 50 80] '
    '/C [0 0 1] /BS << /W 3 >> >>\nendobj\n'
    '8 0 obj\n<< /Type /Annot /Subtype /Circle /Rect [60 20 100 80] '
    '/C [1 0 0] /BS << /W 2 >> >>\nendobj\n'
    'xref\n0 9\n0000000000 65535 f \n'
    'trailer\n<< /Size 9 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

void main() {
  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late DocumentWriter writer;
  late AnnotationEditRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('annot_edit');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    writer = DocumentWriter(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = AnnotationEditRepositoryImpl(library: library, documents: writer);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Uint8List pdf() => Uint8List.fromList(annotatedPdf.codeUnits);

  Future<int> folioCreated() async =>
      (await writer.store(pdf(), 'Folio.pdf')).id;

  Future<int> imported() async {
    final f = File('${root.path}/outside.pdf')..writeAsBytesSync(pdf());
    return (await library.importFile(f.path, displayName: 'Outside.pdf')).id;
  }

  test('loads the annotations already in the document', () async {
    final found = await subject.load(await folioCreated());

    expect(found.map((a) => a.subtype), ['Square', 'Circle']);
  });

  test('a Folio-created document is edited in place', () async {
    final id = await folioCreated();

    final saved = await subject.save(
      documentId: id,
      deleted: {7},
      restyled: const {},
    );

    expect(saved.id, id, reason: 'the same library row');
    expect(await library.all(), hasLength(1));
  });

  test('an imported document produces a new document', () async {
    final id = await imported();

    final saved = await subject.save(
      documentId: id,
      deleted: {7},
      restyled: const {},
    );

    expect(saved.id, isNot(id));
    expect(await library.all(), hasLength(2));
  });

  test('an imported source is left byte-identical', () async {
    final id = await imported();
    final before = await File(
      await library.resolveReadablePath(
        (await library.all()).firstWhere((d) => d.id == id),
      ),
    ).readAsBytes();

    await subject.save(documentId: id, deleted: {7}, restyled: const {});

    final after = await File(
      await library.resolveReadablePath(
        (await library.all()).firstWhere((d) => d.id == id),
      ),
    ).readAsBytes();
    expect(after, before);
  });

  test('the edit is present in the saved bytes', () async {
    final id = await folioCreated();
    final saved = await subject.save(
      documentId: id,
      deleted: {7},
      restyled: const {},
    );

    final text = await File(
      await library.resolveReadablePath(saved),
    ).readAsString();
    // The final page override drops the deleted reference.
    expect(text.lastIndexOf('/Annots [8 0 R]'), greaterThan(0));
  });

  test('saving nothing is rejected before anything is written', () async {
    final id = await folioCreated();

    await expectLater(
      subject.save(documentId: id, deleted: const {}, restyled: const {}),
      throwsA(isA<ArgumentError>()),
    );
    expect(await library.all(), hasLength(1));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/repositories/annotation_edit_repository_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement the repository**

`lib/domain/repositories/annotation_edit_repository.dart`:
```dart
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/models/library_document.dart';

/// Loads annotations already saved in a document, and writes edits back.
abstract interface class AnnotationEditRepository {
  Future<List<SavedAnnotation>> load(int documentId);

  /// Folio-created documents are rewritten in place; imported documents
  /// produce a new document, leaving the imported copy untouched.
  Future<LibraryDocument> save({
    required int documentId,
    required Set<int> deleted,
    required Map<int, AnnotationStyle> restyled,
  });
}
```

`lib/data/repositories/annotation_edit_repository_impl.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/annotation_edit_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class AnnotationEditRepositoryImpl implements AnnotationEditRepository {
  AnnotationEditRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  Future<LibraryDocument> _find(int id) async =>
      (await _library.all()).firstWhere((d) => d.id == id);

  @override
  Future<List<SavedAnnotation>> load(int documentId) async {
    final doc = await _find(documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    // `all`, not a loop over pageCount: pageCount is nullable, and iterating
    // until a page comes back empty would stop at the first unannotated page.
    return PdfAnnotationReader.parse(
      latin1.decode(bytes, allowInvalid: true),
    ).all;
  }

  @override
  Future<LibraryDocument> save({
    required int documentId,
    required Set<int> deleted,
    required Map<int, AnnotationStyle> restyled,
  }) async {
    if (deleted.isEmpty && restyled.isEmpty) {
      throw ArgumentError('nothing to save');
    }

    final doc = await _find(documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    final edited = applyAnnotationEdits(
      bytes,
      deleted: deleted,
      restyled: restyled,
    );

    if (doc.createdByFolio && doc.isManaged) {
      return _library.replaceManagedContent(
        documentId: documentId,
        bytes: edited,
      );
    }

    // Imported: never rewritten. Metadata is re-read from the source so the
    // new document inherits it, exactly as the annotation writer does.
    return _documents.store(
      edited,
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }
}
```

`editedName` lives in `lib/domain/services/edited_name.dart` — import
`package:folio/domain/services/edited_name.dart`, not `document_writer.dart`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/data/repositories/annotation_edit_repository_test.dart`
Expected: PASS — 6 tests

- [ ] **Step 5: Mutation-test the provenance branch**

Change `if (doc.createdByFolio && doc.isManaged)` to `if (true)`. Run the test file.

Expected: `an imported document produces a new document` FAILS. Revert. Without the branch, editing an imported document rewrites the copy the user imported.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: load and save annotation edits, choosing by provenance

A document Folio created is rewritten in place, keeping one library row rather
than accumulating a near-identical document per edit. An imported document
produces a new document and its imported copy is left byte-identical."
```

---

# Stage 3 — The Annotations mode and verification

Ends with: the feature usable on device and proven by rendering on both platforms.

---

### Task 7: The Annotations mode

**Files:**
- Create: `lib/features/viewer/annotation_edit_providers.dart`, `lib/features/viewer/widgets/annotation_selection_overlay.dart`, `lib/features/viewer/widgets/annotation_list_panel.dart`, `lib/features/viewer/widgets/annotation_edit_toolbar.dart`
- Modify: `lib/features/viewer/viewer_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/viewer/annotation_edit_controller_test.dart`

**Interfaces:**
- Consumes: `AnnotationEditSession` (Task 4), `AnnotationEditRepository` (Task 6), `pdfToCanvas` from `page_coordinates.dart`
- Produces: `annotationEditRepositoryProvider`, `annotationEditProvider` (a `NotifierProvider<AnnotationEditController, AnnotationEditState>`) with `load`, `select(int?)`, `deleteSelected()`, `restyleSelected(AnnotationStyle)`, `undo()`, `setBusy(bool)`, `reset()`; `AnnotationEditState` with `session`, `selectedObjectNumber`, `busy`; and `int? annotationAtPoint(...)`

- [ ] **Step 1: Add the strings**

Append to `lib/l10n/app_en.arb`:
```json
{
  "annotationsMode": "Edit annotations",
  "annotationsEmpty": "This page has no annotations.",
  "annotationsDeleteOnly": "Delete only",
  "annotationsDelete": "Delete",
  "annotationsUndo": "Undo",
  "annotationsSave": "Save changes",
  "annotationsSaved": "Saved {name}",
  "annotationsSelectFirst": "Tap an annotation to select it.",
  "annotationsDiscardPrompt": "Discard your changes? The document is unchanged either way."
}
```

Add the placeholder metadata for `annotationsSaved` in the same style as the existing `markupSaved` entry, then run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing controller test**

`test/features/viewer/annotation_edit_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation_edit_session.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/features/viewer/annotation_edit_providers.dart';

SavedAnnotation saved(int number) => SavedAnnotation(
  objectNumber: number,
  pageIndex: 0,
  subtype: 'Square',
  rectPt: const TextRect(left: 0, bottom: 0, right: 10, top: 10),
  rawDictionary: '<< /Subtype /Square >>',
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationEditController c() =>
      container.read(annotationEditProvider.notifier);
  AnnotationEditState s() => container.read(annotationEditProvider);

  test('starts with nothing loaded and nothing selected', () {
    expect(s().session.annotations, isEmpty);
    expect(s().selectedObjectNumber, isNull);
  });

  test('loading replaces the session', () {
    c().loadInto([saved(7), saved(8)]);

    expect(s().session.annotations, hasLength(2));
  });

  test('selecting records the object number', () {
    c()
      ..loadInto([saved(7)])
      ..select(7);

    expect(s().selectedObjectNumber, 7);
  });

  test('deleting the selection stages it and clears the selection', () {
    c()
      ..loadInto([saved(7), saved(8)])
      ..select(7)
      ..deleteSelected();

    expect(s().session.deleted, {7});
    expect(
      s().selectedObjectNumber,
      isNull,
      reason: 'a deleted annotation cannot stay selected',
    );
  });

  test('deleting with nothing selected does nothing', () {
    c()
      ..loadInto([saved(7)])
      ..deleteSelected();

    expect(s().session.isDirty, isFalse);
  });

  test('restyling the selection stages a style', () {
    c()
      ..loadInto([saved(7)])
      ..select(7)
      ..restyleSelected(
        const AnnotationStyle(colorArgb: 0xFFFF0000, strokeWidth: 5),
      );

    expect(s().session.restyled[7]?.strokeWidth, 5);
  });

  test('undo reverses the last edit', () {
    c()
      ..loadInto([saved(7)])
      ..select(7)
      ..deleteSelected();
    c().undo();

    expect(s().session.deleted, isEmpty);
  });

  test('reset clears everything', () {
    c()
      ..loadInto([saved(7)])
      ..select(7)
      ..deleteSelected();
    c().reset();

    expect(s().session.annotations, isEmpty);
    expect(s().selectedObjectNumber, isNull);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/viewer/annotation_edit_controller_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Implement the providers**

`lib/features/viewer/annotation_edit_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation_edit_session.dart';
import 'package:folio/domain/annotations/pdf_annotation_editor.dart';
import 'package:folio/domain/annotations/pdf_annotation_reader.dart';
import 'package:folio/domain/repositories/annotation_edit_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final annotationEditRepositoryProvider = Provider<AnnotationEditRepository>(
  (ref) => throw UnimplementedError(
    'annotationEditRepositoryProvider must be overridden',
  ),
);

class AnnotationEditState {
  const AnnotationEditState({
    required this.session,
    required this.busy,
    this.selectedObjectNumber,
  });

  final AnnotationEditSession session;
  final bool busy;
  final int? selectedObjectNumber;

  AnnotationEditState copyWith({
    bool? busy,
    int? selectedObjectNumber,
    bool clearSelection = false,
  }) => AnnotationEditState(
    session: session,
    busy: busy ?? this.busy,
    selectedObjectNumber: clearSelection
        ? null
        : selectedObjectNumber ?? this.selectedObjectNumber,
  );
}

final annotationEditProvider =
    NotifierProvider<AnnotationEditController, AnnotationEditState>(
      AnnotationEditController.new,
    );

class AnnotationEditController extends Notifier<AnnotationEditState> {
  @override
  AnnotationEditState build() => AnnotationEditState(
    session: AnnotationEditSession(const []),
    busy: false,
  );

  /// The session mutates in place, so emit a new state object to notify
  /// listeners - the same pattern AnnotationController uses.
  void _touch() => state = state.copyWith();

  Future<void> load(int documentId) async {
    final found = await ref.read(annotationEditRepositoryProvider).load(
      documentId,
    );
    loadInto(found);
  }

  void loadInto(List<SavedAnnotation> annotations) {
    state = AnnotationEditState(
      session: AnnotationEditSession(annotations),
      busy: false,
    );
  }

  void select(int? objectNumber) {
    state = objectNumber == null
        ? state.copyWith(clearSelection: true)
        : state.copyWith(selectedObjectNumber: objectNumber);
  }

  void deleteSelected() {
    final selected = state.selectedObjectNumber;
    if (selected == null) return;
    state.session.delete(selected);
    // A deleted annotation cannot stay selected: it is gone from the list.
    state = state.copyWith(clearSelection: true);
  }

  void restyleSelected(AnnotationStyle style) {
    final selected = state.selectedObjectNumber;
    if (selected == null) return;
    state.session.restyle(selected, style);
    _touch();
  }

  void undo() {
    state.session.undo();
    _touch();
  }

  void reset() {
    state = AnnotationEditState(
      session: AnnotationEditSession(const []),
      busy: false,
    );
  }

  void setBusy(bool value) => state = state.copyWith(busy: value);
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/viewer/annotation_edit_controller_test.dart`
Expected: PASS — 8 tests

- [ ] **Step 6: Write the hit-testing test**

Append to `test/features/viewer/annotation_edit_controller_test.dart`:
```dart
  group('hit testing', () {
    const pageRect = Rect.fromLTWH(0, 0, 595, 842);

    SavedAnnotation box(int number, TextRect rect) => SavedAnnotation(
      objectNumber: number,
      pageIndex: 0,
      subtype: 'Square',
      rectPt: rect,
      rawDictionary: '<< >>',
    );

    test('a tap inside an annotation selects it', () {
      final hit = annotationAtPoint(
        const Offset(30, 792),
        annotations: [
          box(7, const TextRect(left: 10, bottom: 20, right: 50, top: 80)),
        ],
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

      expect(hit, 7);
    });

    test('a tap outside every annotation selects nothing', () {
      final hit = annotationAtPoint(
        const Offset(500, 100),
        annotations: [
          box(7, const TextRect(left: 10, bottom: 20, right: 50, top: 80)),
        ],
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

      expect(hit, isNull);
    });

    // A large rectangle must not swallow the small highlight drawn on top.
    test('overlapping annotations resolve smallest-area first', () {
      final hit = annotationAtPoint(
        const Offset(30, 792),
        annotations: [
          box(7, const TextRect(left: 0, bottom: 0, right: 500, top: 800)),
          box(8, const TextRect(left: 10, bottom: 20, right: 50, top: 80)),
        ],
        pageRect: pageRect,
        pageWidthPt: 595,
        pageHeightPt: 842,
      );

      expect(hit, 8);
    });
  });
```

Add `import 'dart:ui';` and the `TextRect` import at the top of the file if they are not already present.

- [ ] **Step 7: Implement hit testing**

Add to `lib/features/viewer/widgets/annotation_selection_overlay.dart`:
```dart
/// The object number of the annotation under [canvasPoint], or null.
///
/// Smallest area first: a large rectangle must not swallow the small highlight
/// drawn on top of it, which is what tapping the topmost match would do.
int? annotationAtPoint(
  Offset canvasPoint, {
  required List<SavedAnnotation> annotations,
  required Rect pageRect,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final candidates =
      annotations.where((a) {
        final rect = _canvasRectOf(
          a,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        );
        return rect.contains(canvasPoint);
      }).toList()..sort((a, b) => _areaOf(a).compareTo(_areaOf(b)));

  return candidates.isEmpty ? null : candidates.first.objectNumber;
}

double _areaOf(SavedAnnotation a) =>
    (a.rectPt.right - a.rectPt.left) * (a.rectPt.top - a.rectPt.bottom);

Rect _canvasRectOf(
  SavedAnnotation a, {
  required Rect pageRect,
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  final topLeft = pdfToCanvas(
    PdfPoint(a.rectPt.left, a.rectPt.top),
    pageRect: pageRect,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  final bottomRight = pdfToCanvas(
    PdfPoint(a.rectPt.right, a.rectPt.bottom),
    pageRect: pageRect,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  return Rect.fromPoints(topLeft, bottomRight);
}
```

Then build `AnnotationSelectionOverlay` as a `ConsumerWidget` in the same file: a `GestureDetector` with `behavior: HitTestBehavior.opaque` whose `onTapUp` calls `annotationAtPoint` and then `controller.select(...)`, wrapping a `CustomPaint` that outlines the selected annotation's rect in the theme's primary colour with a 2px stroke. It takes the same `pageRect`, `pageWidthPt`, `pageHeightPt`, `pageIndex` parameters as `DrawingSurface` does, for the same reason.

- [ ] **Step 8: Run to verify it passes**

Run: `flutter test test/features/viewer/annotation_edit_controller_test.dart`
Expected: PASS — 11 tests

- [ ] **Step 9: Mutation-test the overlap rule**

In `annotationAtPoint`, change the sort to `(a, b) => _areaOf(b).compareTo(_areaOf(a))` so the largest wins. Run the test file.

Expected: `overlapping annotations resolve smallest-area first` FAILS, returning 7 instead of 8. Revert. Largest-first makes a full-page annotation permanently untappable-past.

- [ ] **Step 10: Build the list panel and toolbar**

`annotation_list_panel.dart` — a `ConsumerWidget` listing `session.onPage(pageIndex)`: each row shows the subtype, a colour swatch from `colorArgb` (a neutral outline when null), and the `annotationsDeleteOnly` label when `restylable` is false. Tapping a row calls `controller.select(objectNumber)`. Shows `annotationsEmpty` when the page has none.

`annotation_edit_toolbar.dart` — a `ConsumerWidget` following `DrawingToolbar`'s structure exactly:
- a top row with the selection summary, an undo `IconButton` enabled on `session.canUndo`, and a **pinned** `FilledButton.icon` for Save, enabled on `session.isDirty && !busy`. Save is never placed inside a horizontally scrolling row — that was a real defect in SP-2a.
- a second row with the five `drawingColours` swatches and a thickness `Slider` from 1 to 8, both **disabled** when the selection is not restylable, plus a `Delete` button enabled whenever something is selected.

- [ ] **Step 11: Add the mode to the viewer**

In `lib/features/viewer/viewer_screen.dart`:
- extend `enum _ViewerMode` with `annotations`;
- add `annotations` to `_AnnotateTool` and to the Annotate popup menu, with `l10n.annotationsMode` and `Icons.edit_note`;
- add `_enterAnnotationsMode()` which calls `controller.reset()`, `await controller.load(widget.document.id)` and sets the mode, and `_leaveAnnotationsMode()` which prompts with `l10n.annotationsDiscardPrompt` when `session.isDirty`, mirroring `_leaveDrawMode`;
- add the `annotations` case to the `leading:` switch;
- extend `pageOverlaysBuilder` so it returns `AnnotationSelectionOverlay` in `annotations` mode and `DrawingSurface` in `draw` mode, passing `Offset.zero & pageRect.size` in both cases;
- show `AnnotationEditToolbar` when `_mode == _ViewerMode.annotations`;
- add `_saveAnnotationEdits()` modelled on `_saveAnnotations`, calling `annotationEditRepositoryProvider.save(...)`, then `libraryControllerProvider.notifier.refresh()`, then `controller.reset()` and back to read mode with an `annotationsSaved` snackbar.

**After an in-place save the viewer must reopen the document.** Storage is content-addressed, so the edited document has a new path — reload it by re-resolving the path and assigning `_path`, which rebuilds `PdfViewer.file`. Without this the viewer keeps rendering the superseded file.

- [ ] **Step 12: Wire the repository at app start**

In wherever `annotationRepositoryProvider` is overridden (search for `annotationRepositoryProvider:` in `lib/`), add an override for `annotationEditRepositoryProvider` constructing `AnnotationEditRepositoryImpl(library: ..., documents: ...)` with the same instances.

- [ ] **Step 13: Verify on the simulator**

```bash
flutter build ios --simulator --debug
xcrun simctl install DFC5606D-37F0-4176-A73D-B8214C7F820F build/ios/iphonesimulator/Runner.app
xcrun simctl launch DFC5606D-37F0-4176-A73D-B8214C7F820F dev.folio.app
```

Open a document with saved annotations, enter Edit annotations, tap one, change its colour and thickness, delete another, undo, then save. Confirm the change is visible **immediately** without reopening the document. **Demo this on the simulator.**

Note: any `flutter test integration_test/...` run overwrites `build/ios/iphonesimulator/Runner.app` with the test harness. Rebuild before installing for manual testing or the app launches to a blank screen.

- [ ] **Step 14: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add an Edit annotations mode

Tap an annotation to select it, then restyle or delete it. The overlay exists
only inside the mode, so it cannot compete with the viewer for scroll, pinch or
text selection.

Overlapping annotations resolve smallest-area first: tapping the topmost match
would make a full-page annotation permanently swallow everything drawn on it."
```

---

### Task 8: End-to-end verification and documentation

**Files:**
- Create: `integration_test/annotation_edit_flow_test.dart`
- Modify: `integration_test/all_tests.dart`, `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`

- [ ] **Step 1: Write the end-to-end flows**

`integration_test/annotation_edit_flow_test.dart` builds a real library, saves annotations through `AnnotationRepositoryImpl.saveAnnotations`, then loads and edits them through `AnnotationEditRepositoryImpl`, asserting by **rendering**:

1. deleting one of three annotations stops it drawing — render before and after and require the pixels to differ by more than 200;
2. the other two still draw — after deleting one, the remaining diff against the original is still large;
3. restyling an annotation's colour changes rendered pixels;
4. restyling does **not** move it — the annotation's `/Rect` in the output equals the `/Rect` in the input, string-compared;
5. an in-place save on a Folio-created document keeps one library row and renders the edit;
6. editing an imported document produces a second row and leaves the source SHA-256 unchanged;
7. an annotation Folio did not write (a `/Stamp` injected into a fixture) can still be deleted;
8. metadata survives an edit, so SP-2b has not regressed.

Register it in `integration_test/all_tests.dart`:
```dart
import 'annotation_edit_flow_test.dart' as annotation_edit_flow;
// ...
  group('annotation_edit_flow', annotation_edit_flow.main);
```

- [ ] **Step 2: Run on the iOS simulator**

```bash
flutter test integration_test/all_tests.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including every SP-1, SP-2, SP-3a and SP-3b suite.

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
grep -c "Annots\|Annot" lib/domain/annotations/pdf_object_reader.dart
```

Expected: no matches for the first. The second confirms `PdfObjectReader` still only knows about `/Annots` on page dictionaries — it must not have gained annotation-object parsing.

- [ ] **Step 5: Update the documentation**

- `FEATURES.md` — add an SP-3c table for delete and restyle, ✅ where verified and 🟡 for Windows. State that delete works on annotations from any producer.
- `LIMITATIONS.md` — **remove** the "saved annotations cannot be edited or deleted" entry, replacing it with the narrower truth: geometry cannot be edited, and annotations whose geometry Folio cannot read are delete-only. Add that repeated edits leave superseded appearance streams in the file.
- `ARCHITECTURE.md` — `PdfObjectIndex` and why the last-definition-wins rule lives there; why geometry is copied verbatim; why in-place editing means repointing a row rather than overwriting a path.
- `TESTING.md` — refresh counts and the date.

- [ ] **Step 6: Full verification and push**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
git add -A && git commit -m "test: add end-to-end annotation editing flows and update docs

Every flow reopens the output and requires the change to render. Restyling is
asserted not to move an annotation by comparing its /Rect before and after.
Source documents asserted byte-identical, metadata asserted to survive."
git push -u origin feature/sp3c-annotation-editing
gh pr create --base develop --title "SP-3c: editing and deleting saved annotations"
```

Confirm all four CI jobs pass, including `build-windows`.

---

## Definition of done

- [ ] Delete works on any annotation, including ones Folio did not write
- [ ] Restyle works on annotations whose geometry can be read; others are delete-only and say so
- [ ] Restyle never moves an annotation, proven by mutation and by an end-to-end `/Rect` comparison
- [ ] Folio-created documents edit in place, keeping one library row
- [ ] Imported documents produce a new document and stay byte-identical
- [ ] An in-place edit is visible in the viewer without reopening the document by hand
- [ ] `PdfObjectReader` still handles only page dictionaries
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

**Next:** SP-3d — sticky notes and stamps — and separately, moving and resizing annotations, which should be scoped on its own evidence.
