# SP-3e — Sticky Notes and Stamps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Leave a comment on a document — a sticky note with popup text, or one of six preset stamps.

**Architecture:** `StickyNote` and `Stamp` join the sealed `Annotation` type as `part` files, which makes the writer's two switches non-exhaustive until they are handled. A note carries no appearance stream at all — PDFium draws its icon — while a stamp carries one built from non-embedded Helvetica, sized from its label rather than measured. Editing a saved note's text extends `AnnotationStyle` with an optional `contents`.

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5, pdfrx 2.4.7 (PDFium), drift 2.34.3, flutter_riverpod 3.3.2.

**Spec:** `docs/superpowers/specs/2026-08-26-sp3e-notes-and-stamps-design.md`

## Global Constraints

- **Zero AI, zero paid or proprietary SDKs, no GPL/LGPL/AGPL.** No new dependencies, and **no embedded fonts** — Helvetica is referenced, never embedded.
- **Never destroy originals.** Placement goes through `saveAnnotations`, which already writes a new document.
- **`PdfEngine` has no write method and must not gain one.**
- **`PdfObjectReader` handles page dictionaries and nothing else.**
- **Never log document content** — a note's text is document content.
- **Folio stamps no `/Producer`, no `/ModDate`, and no ownership marker.**
- **A feature is not done until it has been verified by rendering.**
- Run `dart format lib test integration_test scripts` and `flutter analyze --fatal-infos` before every commit.

## Critical context the implementer will not guess

**Probed on device 2026-08-26, not assumed:**

| Question | Answer |
|---|---|
| Does PDFium draw a `/Text` note without an `/AP`? | **Yes** — 692 pixels changed |
| Does non-embedded standard-14 `/Helvetica` render? | **Yes** — 3927 pixels changed |
| Does a `/Stamp` render without an `/AP`? | **No** — 0 pixels changed |

**The writer emits an `/AP` for every annotation today.** In `writeAnnotations`, `final apNum = nextObj++; emit(apNum, ...)` runs unconditionally inside the per-annotation loop. Notes must not get one, so the appearance becomes nullable and the `/AP` entry conditional.

**Two switches over the sealed type must be extended**, not one: the `(stream, dict)` switch in `writeAnnotations`, and the one in `_annotationDict`. Dart will refuse to compile until both are exhaustive — that is the point of sealing.

**Dart permits a sealed type to be extended only inside its own library.** `sticky_note.dart` and `stamp.dart` are therefore `part` files of `annotation.dart`, exactly like `text_markup.dart` and `drawing_annotation.dart`. Part files carry no imports of their own.

**`AnnotationStyle` already defines `==` and `hashCode`.** Both must include `contents`, or two different note edits compare equal and the session — which keeps one style per object — silently discards one.

## File structure

| File | Responsibility |
|---|---|
| `lib/domain/annotations/sticky_note.dart` | **New**, `part of annotation.dart`. The `StickyNote` type. |
| `lib/domain/annotations/stamp.dart` | **New**, `part of annotation.dart`. `StampPreset` and `Stamp`. |
| `lib/domain/annotations/annotation.dart` | **Modify.** Two new `part` directives. |
| `lib/domain/annotations/stamp_appearance.dart` | **New.** Appearance stream, dictionary, and the shared font object. |
| `lib/domain/annotations/pdf_annotation_writer.dart` | **Modify.** Optional appearance, shared font object, both switches. |
| `lib/domain/annotations/pdf_annotation_reader.dart` | **Modify.** Reconstructs a `StickyNote`. |
| `lib/domain/annotations/pdf_annotation_editor.dart` | **Modify.** `AnnotationStyle.contents`; notes get no `/AP`. |
| `lib/features/viewer/annotation_providers.dart` | **Modify.** `addNote`, `addStamp`. |
| `lib/features/viewer/widgets/note_dialog.dart` | **New.** Text entry, used when placing and when editing. |
| `lib/features/viewer/widgets/stamp_picker.dart` | **New.** The six presets. |
| `lib/features/viewer/widgets/tap_placement_surface.dart` | **New.** One tap-to-place overlay serving both modes. |
| `lib/features/viewer/widgets/annotation_edit_toolbar.dart` | **Modify.** Edit note text; disable thickness for notes. |
| `lib/features/viewer/viewer_screen.dart` | **Modify.** `_ViewerMode.note` and `_ViewerMode.stamp`. |

---

# Stage 1 — The types and the write path

Ends with: notes and stamps written into a real PDF.

---

### Task 1: StickyNote, Stamp and the stamp appearance

**Files:**
- Create: `lib/domain/annotations/sticky_note.dart`, `lib/domain/annotations/stamp.dart`, `lib/domain/annotations/stamp_appearance.dart`
- Modify: `lib/domain/annotations/annotation.dart`
- Test: `test/domain/annotations/notes_and_stamps_test.dart`

**Interfaces:**
- Consumes: `Annotation`, `PdfPoint`, `pdfNumber` from `pdf_appearance.dart`
- Produces: `StickyNote({required int pageIndex, required PdfPoint anchorPt, required String contents, int colorArgb})` with `static const double iconSizePt = 20`; `enum StampPreset { approved, rejected, draft, confidential, reviewed, urgent }`; `Stamp({required StampPreset preset, required int pageIndex, required PdfPoint anchorPt})` with `String get label`, `int get colorArgb`, `double get widthPt`, `double get heightPt`; `String stampAppearanceStream(Stamp)`, `String stampAppearanceDict(Stamp, int streamLength, int fontObjectNumber)`, `String helveticaFontObject()`

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/notes_and_stamps_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/annotations/stamp_appearance.dart';

const note = StickyNote(
  pageIndex: 0,
  anchorPt: PdfPoint(100, 700),
  contents: 'Check this clause',
);

const approved = Stamp(
  preset: StampPreset.approved,
  pageIndex: 0,
  anchorPt: PdfPoint(100, 700),
);

const confidential = Stamp(
  preset: StampPreset.confidential,
  pageIndex: 0,
  anchorPt: PdfPoint(100, 700),
);

void main() {
  group('sticky notes', () {
    test('is a Text annotation', () {
      expect(note.pdfSubtype, 'Text');
    });

    test('is an Annotation', () {
      expect(note, isA<Annotation>());
    });

    test('carries its contents', () {
      expect(note.contents, 'Check this clause');
    });

    test('has a fixed icon size', () {
      expect(StickyNote.iconSizePt, 20);
    });
  });

  group('stamps', () {
    test('is a Stamp annotation', () {
      expect(approved.pdfSubtype, 'Stamp');
    });

    test('every preset has a label and a colour', () {
      for (final preset in StampPreset.values) {
        final s = Stamp(
          preset: preset,
          pageIndex: 0,
          anchorPt: const PdfPoint(0, 0),
        );
        expect(s.label, isNotEmpty);
        expect(s.colorArgb, isNot(0));
      }
    });

    // Sized from the label rather than measured: a fixed width clips the long
    // ones and wastes space on the short ones.
    test('a longer label gives a wider box', () {
      expect(confidential.widthPt, greaterThan(approved.widthPt));
    });

    test('height does not depend on the label', () {
      expect(confidential.heightPt, approved.heightPt);
    });
  });

  group('stamp appearance', () {
    test('draws the label as text', () {
      final s = stampAppearanceStream(approved);

      expect(s, contains('BT'));
      expect(s, contains('ET'));
      expect(s, contains('(APPROVED) Tj'));
    });

    test('names the font resource it will be given', () {
      expect(stampAppearanceStream(approved), contains('/F1'));
    });

    test('draws a box around the label', () {
      expect(stampAppearanceStream(approved), contains('re'));
    });

    test('the dictionary references the font object', () {
      final d = stampAppearanceDict(approved, 42, 9);

      expect(d, contains('/Type /XObject'));
      expect(d, contains('/Subtype /Form'));
      expect(d, contains('/Length 42'));
      expect(d, contains('/Font << /F1 9 0 R >>'));
    });

    test('the BBox matches the stamp box', () {
      final d = stampAppearanceDict(approved, 42, 9);
      expect(
        d,
        contains(
          '/BBox [0 0 ${approved.widthPt.round()} '
          '${approved.heightPt.round()}]',
        ),
      );
    });

    // Standard-14: referenced, never embedded. Embedding a font would be a new
    // dependency on font data we do not have a licence to redistribute.
    test('the font object is a non-embedded standard-14 Helvetica', () {
      final f = helveticaFontObject();

      expect(f, contains('/BaseFont /Helvetica'));
      expect(f, contains('/Subtype /Type1'));
      expect(f, isNot(contains('/FontFile')));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/notes_and_stamps_test.dart`
Expected: FAIL — `Undefined name 'StickyNote'`

- [ ] **Step 3: Add the note type**

`lib/domain/annotations/sticky_note.dart`:
```dart
part of 'annotation.dart';

/// A comment anchored to a point on the page.
///
/// Written as a PDF /Text annotation, which viewers draw as an icon and open
/// as a popup. It carries NO appearance stream: PDFium draws the icon itself,
/// and generating one would only risk disagreeing with what other viewers
/// draw. The text lives in /Contents, where it stays searchable and copyable.
final class StickyNote extends Annotation {
  const StickyNote({
    required this.pageIndex,
    required this.anchorPt,
    required this.contents,
    this.colorArgb = 0xFFFFC107,
  });

  @override
  final int pageIndex;

  /// Top-left of the icon, in PDF user space.
  final PdfPoint anchorPt;

  final String contents;
  final int colorArgb;

  @override
  String get pdfSubtype => 'Text';

  /// PDF's conventional note icon size. Viewers draw the icon at a fixed size
  /// regardless, so there is nothing for the user to size.
  static const double iconSizePt = 20;
}
```

- [ ] **Step 4: Add the stamp type**

`lib/domain/annotations/stamp.dart`:
```dart
part of 'annotation.dart';

enum StampPreset { approved, rejected, draft, confidential, reviewed, urgent }

/// One of a fixed set of preset marks.
///
/// Unlike a note, a /Stamp renders nothing without an appearance stream -
/// probed on device: zero pixels changed - so one is always generated.
final class Stamp extends Annotation {
  const Stamp({
    required this.preset,
    required this.pageIndex,
    required this.anchorPt,
  });

  final StampPreset preset;

  @override
  final int pageIndex;

  /// Top-left of the box, in PDF user space.
  final PdfPoint anchorPt;

  @override
  String get pdfSubtype => 'Stamp';

  String get label => switch (preset) {
    StampPreset.approved => 'APPROVED',
    StampPreset.rejected => 'REJECTED',
    StampPreset.draft => 'DRAFT',
    StampPreset.confidential => 'CONFIDENTIAL',
    StampPreset.reviewed => 'REVIEWED',
    StampPreset.urgent => 'URGENT',
  };

  int get colorArgb => switch (preset) {
    StampPreset.approved => 0xFF388E3C,
    StampPreset.rejected => 0xFFD32F2F,
    StampPreset.draft => 0xFF616161,
    StampPreset.confidential => 0xFFD32F2F,
    StampPreset.reviewed => 0xFF1976D2,
    StampPreset.urgent => 0xFFF9A825,
  };

  static const double fontSizePt = 14;
  static const double paddingPt = 8;

  /// Sized from the label rather than measured. 0.75 em is a safe upper bound
  /// for uppercase Helvetica, so the text always fits by construction; a fixed
  /// width would clip CONFIDENTIAL and waste space on DRAFT. Carrying a width
  /// table for a font we do not embed is not worth the accuracy.
  double get widthPt => 2 * paddingPt + label.length * fontSizePt * 0.75;

  double get heightPt => fontSizePt + 2 * paddingPt;
}
```

In `lib/domain/annotations/annotation.dart`, add beside the existing directives:
```dart
part 'stamp.dart';
part 'sticky_note.dart';
```

- [ ] **Step 5: Add the stamp appearance**

`lib/domain/annotations/stamp_appearance.dart`:
```dart
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart' show pdfNumber;

/// Content stream drawing a stamp: a box, then its label.
///
/// Coordinates are local to the appearance's BBox, which starts at the origin,
/// so the same stream works wherever the stamp is placed.
String stampAppearanceStream(Stamp stamp) {
  String channel(int shift) =>
      pdfNumber(((stamp.colorArgb >> shift) & 0xFF) / 255);
  final colour = '${channel(16)} ${channel(8)} ${channel(0)}';

  final w = stamp.widthPt;
  final h = stamp.heightPt;
  const inset = 1.0;

  return StringBuffer()
    ..writeln('$colour RG')
    ..writeln('$colour rg')
    ..writeln('2 w')
    ..writeln(
      '${pdfNumber(inset)} ${pdfNumber(inset)} '
      '${pdfNumber(w - 2 * inset)} ${pdfNumber(h - 2 * inset)} re',
    )
    ..writeln('S')
    ..writeln('BT')
    ..writeln('/F1 ${pdfNumber(Stamp.fontSizePt)} Tf')
    ..writeln(
      '${pdfNumber(Stamp.paddingPt)} ${pdfNumber(Stamp.paddingPt)} Td',
    )
    ..writeln('(${_escape(stamp.label)}) Tj')
    ..writeln('ET')
    ..toString();
}

/// The form XObject wrapping [stampAppearanceStream].
///
/// [fontObjectNumber] is the shared Helvetica object; every stamp in a save
/// references the same one.
String stampAppearanceDict(Stamp stamp, int streamLength, int fontObjectNumber) =>
    '<< /Type /XObject /Subtype /Form '
    '/BBox [0 0 ${pdfNumber(stamp.widthPt)} ${pdfNumber(stamp.heightPt)}] '
    '/Resources << /Font << /F1 $fontObjectNumber 0 R >> >> '
    '/Length $streamLength >>';

/// A standard-14 font: referenced, never embedded.
///
/// The fourteen standard fonts are built into every conforming viewer, so no
/// font data is shipped and no font licence is involved. Verified on device:
/// a non-embedded /Helvetica renders.
String helveticaFontObject() =>
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
    '/Encoding /WinAnsiEncoding >>';

```

`_escape` is **not** defined here. Add it once to `pdf_appearance.dart`, beside
`pdfNumber`, and import it — the writer and the editor need the same function,
and three private copies of an escaping rule is how one of them ends up wrong:

```dart
/// Wraps [text] as a PDF literal string, escaping the characters that would
/// otherwise end it early. Shared so every writer escapes identically.
String pdfString(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
  return '($escaped)';
}
```

Then `stampAppearanceStream` writes `'${pdfString(stamp.label)} Tj'`.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/domain/annotations/notes_and_stamps_test.dart`
Expected: PASS — 13 tests

Note: the whole suite will NOT compile yet, because the writer's two switches
are no longer exhaustive. Task 2 fixes that; this step runs the one file.

- [ ] **Step 7: Mutation-test the label sizing**

In `stamp.dart`, change `widthPt` to `double get widthPt => 120;`. Run the test file.

Expected: `a longer label gives a wider box` FAILS. Revert.

- [ ] **Step 8: Commit**

```bash
dart format lib test
git add -A
git commit -m "feat: add sticky note and stamp annotation types

A note carries no appearance stream: PDFium draws the icon itself, verified on
device, and generating one would risk disagreeing with other viewers. A stamp
renders nothing without one, so it always gets one.

The stamp box is sized from its label rather than measured. 0.75 em is a safe
upper bound for uppercase Helvetica, so text fits by construction; carrying a
width table for a font we do not embed is not worth the accuracy."
```

---

### Task 2: Writing notes and stamps

**Files:**
- Modify: `lib/domain/annotations/pdf_annotation_writer.dart`
- Test: `test/domain/annotations/pdf_annotation_writer_test.dart`

**Interfaces:**
- Consumes: `StickyNote`, `Stamp`, `stampAppearanceStream`, `stampAppearanceDict`, `helveticaFontObject` (Task 1)
- Produces: `writeAnnotations` handling all four annotation kinds

- [ ] **Step 1: Add the failing tests**

Append to `test/domain/annotations/pdf_annotation_writer_test.dart`:
```dart
  group('notes and stamps', () {
    const note = StickyNote(
      pageIndex: 0,
      anchorPt: PdfPoint(100, 700),
      contents: 'Check this clause',
    );
    const approved = Stamp(
      preset: StampPreset.approved,
      pageIndex: 0,
      anchorPt: PdfPoint(100, 600),
    );

    test('a note is written as /Text with its contents', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [note]));

      expect(text, contains('/Subtype /Text'));
      expect(text, contains('(Check this clause)'));
      expect(text, contains('/Name /Note'));
    });

    test('a note is anchored at an icon-sized /Rect', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [note]));
      expect(text, contains('/Rect [100 680 120 700]'));
    });

    // PDFium draws the icon itself. An /AP we generated could only disagree
    // with what other viewers draw.
    test('a note carries NO appearance stream', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [note]));

      expect(text, isNot(contains('/AP')));
      expect(text, isNot(contains('/Subtype /Form')));
    });

    test('a stamp is written with an appearance stream', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [approved]));

      expect(text, contains('/Subtype /Stamp'));
      expect(text, contains('/AP'));
      expect(text, contains('(APPROVED) Tj'));
    });

    test('a stamp names its preset', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [approved]));
      expect(text, contains('/Name /Approved'));
    });

    // One font object per save, not one per stamp.
    test('several stamps share one font object', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [
          approved,
          const Stamp(
            preset: StampPreset.draft,
            pageIndex: 0,
            anchorPt: PdfPoint(300, 600),
          ),
        ]),
      );

      expect(RegExp(r'/BaseFont /Helvetica').allMatches(text).length, 1);
    });

    test('a document with no stamps emits no font object', () {
      final text = latin1.decode(writeAnnotations(classicPdf(), [note]));
      expect(text, isNot(contains('/BaseFont')));
    });

    // The point of the sealed type: every kind in one pass.
    test('all four annotation kinds write together', () {
      final text = latin1.decode(
        writeAnnotations(classicPdf(), [markup(), note, approved]),
      );

      expect(text, contains('/Subtype /Highlight'));
      expect(text, contains('/Subtype /Text'));
      expect(text, contains('/Subtype /Stamp'));
      // Still exactly one page override.
      expect(RegExp(r'3 0 obj').allMatches(text).length, 2);
    });
  });
```

Add imports for `pdf_point.dart` if not already present.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_annotation_writer_test.dart`
Expected: FAIL — the switch on `annotation` is not exhaustive.

- [ ] **Step 3: Make the appearance optional and share the font**

In `lib/domain/annotations/pdf_annotation_writer.dart`, add the import:
```dart
import 'package:folio/domain/annotations/stamp_appearance.dart';
```

Before the `for (final entry in byPage.entries)` loop, emit the font once if any
stamp is present:
```dart
  // One font object per save, shared by every stamp. Standard-14: referenced,
  // never embedded.
  int? fontObjNum;
  if (annotations.any((a) => a is Stamp)) {
    fontObjNum = nextObj++;
    emit(fontObjNum, helveticaFontObject());
  }
```

Replace the per-annotation emission block with:
```dart
    final newRefs = <String>[];
    for (final annotation in entry.value) {
      // Nullable: a /Text note has no appearance stream at all.
      final (String, String)? appearance = switch (annotation) {
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
        Stamp() => (
          stampAppearanceStream(annotation),
          stampAppearanceDict(
            annotation,
            stampAppearanceStream(annotation).length,
            fontObjNum!,
          ),
        ),
        StickyNote() => null,
      };

      int? apNum;
      if (appearance != null) {
        final (stream, dict) = appearance;
        apNum = nextObj++;
        emit(apNum, '$dict\nstream\n${stream}endstream');
      }

      final annotNum = nextObj++;
      emit(annotNum, _annotationDict(annotation, apNum));
      newRefs.add('$annotNum 0 R');
    }
```

- [ ] **Step 4: Extend the dictionary builder**

In `_annotationDict`, change the signature to `String _annotationDict(Annotation annotation, int? apNum)` and make the `/AP` entry conditional:
```dart
  final ap = apNum == null ? '' : ' /AP << /N $apNum 0 R >>';
```

Then remove the leading space from each existing use of `$ap` so the spacing
stays correct — the entry now carries its own leading space, or is empty.

Add the two new cases:
```dart
    case StickyNote():
      final r = annotation.anchorPt;
      const size = StickyNote.iconSizePt;
      return '<< /Type /Annot /Subtype /Text '
          '/Rect [${pdfNumber(r.x)} ${pdfNumber(r.y - size)} '
          '${pdfNumber(r.x + size)} ${pdfNumber(r.y)}] '
          '/Contents (${_escapeString(annotation.contents)}) '
          '/Name /Note /C [${_colourOf(annotation.colorArgb)}] /CA 1 /F 4'
          '$ap >>';

    case Stamp():
      final r = annotation.anchorPt;
      // /Name records the preset so a reader can tell them apart.
      final name = annotation.preset.name;
      final capitalised =
          name[0].toUpperCase() + name.substring(1);
      return '<< /Type /Annot /Subtype /Stamp '
          '/Rect [${pdfNumber(r.x)} ${pdfNumber(r.y - annotation.heightPt)} '
          '${pdfNumber(r.x + annotation.widthPt)} ${pdfNumber(r.y)}] '
          '/Name /$capitalised '
          '/C [${_colourOf(annotation.colorArgb)}] /CA 1 /F 4'
          '$ap >>';
```

Add one helper at the bottom of the file, and use the shared `pdfString` from
`pdf_appearance.dart` for the text:
```dart
String _colourOf(int argb) {
  String channel(int shift) => pdfNumber(((argb >> shift) & 0xFF) / 255);
  return '${channel(16)} ${channel(8)} ${channel(0)}';
}
```

In the two cases above, write `/Contents ${pdfString(annotation.contents)}`
rather than escaping inline.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_annotation_writer_test.dart`
Expected: PASS — the SP-3a/3b tests plus 8 new.

- [ ] **Step 6: Run the whole suite**

Run: `dart format lib test && flutter analyze --fatal-infos && flutter test`
Expected: all pass. Every earlier annotation test is the guard that making the appearance optional changed nothing for the kinds that have one.

- [ ] **Step 7: Mutation-test the note's missing appearance**

In the emission switch, change `StickyNote() => null,` to give notes a drawing-style appearance:
```dart
        StickyNote() => ('0 0 0 RG\n', '<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] /Length 10 >>'),
```
Run: `flutter test test/domain/annotations/pdf_annotation_writer_test.dart`

Expected: `a note carries NO appearance stream` FAILS. Revert.

Then change the font emission condition to `if (true)`. Run the same file.

Expected: `a document with no stamps emits no font object` FAILS. Revert.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: write sticky notes and stamps

A note is written with no appearance stream: PDFium draws the icon itself, and
generating one would risk disagreeing with what other viewers draw. A stamp
always gets one, because it renders nothing without.

One shared Helvetica object per save rather than one per stamp, and none at all
when no stamp is present."
```

---

# Stage 2 — Reading and editing

Ends with: a saved note's text editable through the SP-3c flow.

---

### Task 3: Reading notes back and editing their text

**Files:**
- Modify: `lib/domain/annotations/pdf_annotation_reader.dart`, `lib/domain/annotations/pdf_annotation_editor.dart`
- Test: `test/domain/annotations/pdf_annotation_reader_test.dart`, `test/domain/annotations/pdf_annotation_editor_test.dart`

**Interfaces:**
- Consumes: `StickyNote` (Task 1)
- Produces: `AnnotationStyle({required int colorArgb, required double strokeWidth, String? contents})` with `contents` in `==` and `hashCode`

- [ ] **Step 1: Add the failing reader tests**

Append to `test/domain/annotations/pdf_annotation_reader_test.dart`:
```dart
  group('notes and stamps', () {
    const noteObj =
        '7 0 obj\n<< /Type /Annot /Subtype /Text /Rect [100 680 120 700] '
        '/Contents (Check this clause) /Name /Note /C [1 0.76 0.03] >>\n'
        'endobj\n';
    const stampObj =
        '8 0 obj\n<< /Type /Annot /Subtype /Stamp /Rect [100 560 220 600] '
        '/Name /Approved /C [0.22 0.56 0.24] >>\nendobj\n';

    test('a note is reconstructed with its text', () {
      final a = PdfAnnotationReader.parse(
        docWith('7 0 R', noteObj),
      ).onPage(0).single;

      expect(a.restylable, isTrue);
      final note = a.reconstructed! as StickyNote;
      expect(note.contents, 'Check this clause');
    });

    test('a note keeps its anchor', () {
      final a = PdfAnnotationReader.parse(
        docWith('7 0 R', noteObj),
      ).onPage(0).single;

      final note = a.reconstructed! as StickyNote;
      expect(note.anchorPt.x, 100);
      expect(note.anchorPt.y, 700);
    });

    // Scoped out of SP-3e: reconstructing a stamp is possible but not built,
    // and a control that does nothing is worse than an honest label.
    test('a stamp is delete-only', () {
      final a = PdfAnnotationReader.parse(
        docWith('8 0 R', stampObj),
      ).onPage(0).single;

      expect(a.subtype, 'Stamp');
      expect(a.restylable, isFalse);
    });

    test('an escaped parenthesis in the text survives', () {
      const escaped =
          '7 0 obj\n<< /Type /Annot /Subtype /Text /Rect [100 680 120 700] '
          r'/Contents (see \(b\) below) /Name /Note >>' '\nendobj\n';

      final note =
          PdfAnnotationReader.parse(
                docWith('7 0 R', escaped),
              ).onPage(0).single.reconstructed!
              as StickyNote;

      expect(note.contents, 'see (b) below');
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_annotation_reader_test.dart`
Expected: FAIL — the note reconstructs as null, so `restylable` is false.

- [ ] **Step 3: Reconstruct notes**

In `lib/domain/annotations/pdf_annotation_reader.dart`, add to `_reconstruct` before the markup branch:
```dart
    if (subtype == 'Text') {
      return StickyNote(
        pageIndex: pageIndex,
        // /Rect is [left bottom right top]; the anchor is the top-left.
        anchorPt: PdfPoint(rectPt.left, rectPt.top),
        contents: _contentsOf(dict) ?? '',
        colorArgb: colorArgb,
      );
    }
```

And add the reader:
```dart
  /// The `/Contents` literal string, with PDF escapes undone.
  static String? _contentsOf(String dict) {
    final start = dict.indexOf('/Contents');
    if (start < 0) return null;
    final open = dict.indexOf('(', start);
    if (open < 0) return null;

    final buffer = StringBuffer();
    var depth = 0;
    for (var i = open; i < dict.length; i++) {
      final c = dict[i];
      if (c == r'\' && i + 1 < dict.length) {
        buffer.write(dict[i + 1]);
        i++;
        continue;
      }
      if (c == '(') {
        depth++;
        if (depth == 1) continue;
      }
      if (c == ')') {
        depth--;
        if (depth == 0) return buffer.toString();
      }
      buffer.write(c);
    }
    return null;
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_annotation_reader_test.dart`
Expected: PASS — the SP-3c tests plus 4 new.

- [ ] **Step 5: Add the failing editor tests**

Append to `test/domain/annotations/pdf_annotation_editor_test.dart`:
```dart
  group('editing note text', () {
    Uint8List withNote() => Uint8List.fromList(
      latin1.encode(
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Annots [7 0 R] >>\nendobj\n'
        '7 0 obj\n<< /Type /Annot /Subtype /Text /Rect [100 680 120 700] '
        '/Contents (Original text) /Name /Note /C [1 0.76 0.03] >>\nendobj\n'
        'xref\n0 8\n0000000000 65535 f \n'
        'trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
      ),
    );

    test('rewrites /Contents', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          withNote(),
          deleted: const {},
          restyled: {
            7: const AnnotationStyle(
              colorArgb: 0xFFFFC107,
              strokeWidth: 2,
              contents: 'Corrected text',
            ),
          },
        ),
      );

      final override = RegExp(
        r'7 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      expect(override, contains('(Corrected text)'));
      expect(override, isNot(contains('(Original text)')));
    });

    test('leaves /Rect untouched', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          withNote(),
          deleted: const {},
          restyled: {
            7: const AnnotationStyle(
              colorArgb: 0xFFFFC107,
              strokeWidth: 2,
              contents: 'Corrected text',
            ),
          },
        ),
      );

      final override = RegExp(
        r'7 0 obj\s*(<<.*?>>)\s*endobj',
        dotAll: true,
      ).allMatches(text).last.group(1)!;

      expect(override, contains('/Rect [100 680 120 700]'));
    });

    // A note has no appearance stream; adding one would disagree with the icon
    // every viewer already draws.
    test('emits no appearance stream for a note', () {
      final text = latin1.decode(
        applyAnnotationEdits(
          withNote(),
          deleted: const {},
          restyled: {
            7: const AnnotationStyle(
              colorArgb: 0xFFFFC107,
              strokeWidth: 2,
              contents: 'Corrected text',
            ),
          },
        ),
      );

      expect(text, isNot(contains('/Subtype /Form')));
    });

    // The session keeps one style per object. If contents were left out of
    // equality, two different edits would compare equal and one would vanish.
    test('two styles differing only in contents are not equal', () {
      const a = AnnotationStyle(
        colorArgb: 0xFF000000,
        strokeWidth: 2,
        contents: 'one',
      );
      const b = AnnotationStyle(
        colorArgb: 0xFF000000,
        strokeWidth: 2,
        contents: 'two',
      );

      expect(a, isNot(b));
    });
  });
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_annotation_editor_test.dart`
Expected: FAIL — `No named parameter with the name 'contents'`

- [ ] **Step 7: Extend AnnotationStyle and the override**

In `lib/domain/annotations/pdf_annotation_editor.dart`:
```dart
class AnnotationStyle {
  const AnnotationStyle({
    required this.colorArgb,
    required this.strokeWidth,
    this.contents,
  });

  final int colorArgb;
  final double strokeWidth;

  /// New text for a sticky note. Null leaves the existing text alone.
  final String? contents;

  @override
  bool operator ==(Object other) =>
      other is AnnotationStyle &&
      other.colorArgb == colorArgb &&
      other.strokeWidth == strokeWidth &&
      other.contents == contents;

  @override
  int get hashCode => Object.hash(colorArgb, strokeWidth, contents);
}
```

In the restyle loop, skip the appearance for a note:
```dart
    final restyledAnnotation = _withStyle(target!.reconstructed!, entry.value);

    // A note has no appearance stream; adding one would disagree with the icon
    // every viewer already draws.
    int? apNum;
    if (restyledAnnotation is! StickyNote) {
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
        StickyNote() || Stamp() => throw StateError('unreachable'),
      };
      apNum = nextObj++;
      emit(apNum, '$dict\nstream\n${stream}endstream');
    }

    emit(
      target.objectNumber,
      _restyledDictionary(target.rawDictionary, entry.value, apNum),
    );
```

Extend `_withStyle` for notes:
```dart
      StickyNote() => StickyNote(
        pageIndex: annotation.pageIndex,
        anchorPt: annotation.anchorPt,
        contents: style.contents ?? annotation.contents,
        colorArgb: style.colorArgb,
      ),
      Stamp() => annotation,
```

And make `_restyledDictionary` take a nullable `apNum`, rewrite `/Contents` when
the style carries it, and omit `/BS` for a note (an icon has no stroke):
```dart
String _restyledDictionary(String source, AnnotationStyle style, int? apNum) {
  String colour(int shift) =>
      pdfNumber(((style.colorArgb >> shift) & 0xFF) / 255);
  final c = '/C [${colour(16)} ${colour(8)} ${colour(0)}]';
  final isNote = RegExp(r'/Subtype\s*/Text\b').hasMatch(source);
  final bs = isNote ? '' : ' /BS << /W ${pdfNumber(style.strokeWidth)} >>';
  final ap = apNum == null ? '' : ' /AP << /N $apNum 0 R >>';

  var body = source.substring(2, source.length - 2).trim();
  body = body.replaceAll(RegExp(r'/C\s*\[[^\]]*\]'), '');
  body = body.replaceAll(RegExp(r'/BS\s*<<[^>]*>>'), '');
  body = body.replaceAll(RegExp(r'/AP\s*<<[^>]*>>'), '');
  if (style.contents != null) {
    body = body.replaceAll(
      RegExp(r'/Contents\s*\([^)]*\)'),
      '/Contents ${pdfString(style.contents!)}',
    );
  }
  body = body.replaceAll(RegExp(r'\s+'), ' ').trim();

  return '<< $body $c$bs$ap >>';
}
```

- [ ] **Step 8: Run to verify it passes**

Run: `dart format lib test && flutter analyze --fatal-infos && flutter test`
Expected: all pass, including every SP-3c test.

- [ ] **Step 9: Mutation-test equality and the note appearance**

Remove `other.contents == contents` from `==`. Run the editor test file.

Expected: `two styles differing only in contents are not equal` FAILS. Revert.

Then change `if (restyledAnnotation is! StickyNote)` to `if (true)`. Run again.

Expected: `emits no appearance stream for a note` FAILS **and** the switch throws `StateError`. Revert.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: read notes back and edit their text

AnnotationStyle gains an optional contents, included in == and hashCode: the
session keeps one style per object, so two edits comparing equal would silently
discard one.

A note override rewrites /Contents, omits /BS because an icon has no stroke,
and emits no appearance stream. Geometry is still copied verbatim."
```

---

# Stage 3 — Placing them, and verification

Ends with: notes and stamps placed on device and proven by rendering.

---

### Task 4: Placement modes

**Files:**
- Create: `lib/features/viewer/widgets/note_dialog.dart`, `lib/features/viewer/widgets/stamp_picker.dart`, `lib/features/viewer/widgets/tap_placement_surface.dart`
- Modify: `lib/features/viewer/annotation_providers.dart`, `lib/features/viewer/widgets/annotation_edit_toolbar.dart`, `lib/features/viewer/viewer_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/viewer/note_stamp_placement_test.dart`

**Interfaces:**
- Consumes: `StickyNote`, `Stamp`, `StampPreset` (Task 1), `canvasToPdf` from `page_coordinates.dart`
- Produces: `AnnotationController.addNote({required int pageIndex, required PdfPoint anchorPt, required String contents})` and `AnnotationController.addStamp({required StampPreset preset, required int pageIndex, required PdfPoint anchorPt})`

- [ ] **Step 1: Add the strings**

Append to `lib/l10n/app_en.arb`:
```json
{
  "noteMode": "Sticky note",
  "noteText": "Note",
  "noteHint": "What do you want to say?",
  "notePlaceHint": "Tap where the note should go.",
  "noteEmpty": "A note needs some text.",
  "stampMode": "Stamp",
  "stampPlaceHint": "Tap where the stamp should go.",
  "stampApproved": "Approved",
  "stampRejected": "Rejected",
  "stampDraft": "Draft",
  "stampConfidential": "Confidential",
  "stampReviewed": "Reviewed",
  "stampUrgent": "Urgent"
}
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing test**

`test/features/viewer/note_stamp_placement_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationController c() =>
      container.read(annotationSessionProvider.notifier);
  AnnotationState s() => container.read(annotationSessionProvider);

  test('placing a note stages one annotation with its text', () {
    c().addNote(
      pageIndex: 0,
      anchorPt: const PdfPoint(100, 700),
      contents: 'Check this',
    );

    final note = s().session.annotations.single as StickyNote;
    expect(note.contents, 'Check this');
    expect(note.anchorPt.x, 100);
  });

  // An empty note is invisible in the popup and clutters the page with an icon
  // that says nothing.
  test('an empty note is not staged', () {
    c().addNote(
      pageIndex: 0,
      anchorPt: const PdfPoint(100, 700),
      contents: '   ',
    );

    expect(s().session.annotations, isEmpty);
  });

  test('placing a stamp stages one annotation with its preset', () {
    c().addStamp(
      preset: StampPreset.approved,
      pageIndex: 1,
      anchorPt: const PdfPoint(50, 500),
    );

    final stamp = s().session.annotations.single as Stamp;
    expect(stamp.preset, StampPreset.approved);
    expect(stamp.pageIndex, 1);
  });

  test('undo removes a placed stamp', () {
    c().addStamp(
      preset: StampPreset.draft,
      pageIndex: 0,
      anchorPt: const PdfPoint(50, 500),
    );
    c().undo();

    expect(s().session.annotations, isEmpty);
  });

  test('notes and stamps share the session with drawings', () {
    c()
      ..addNote(
        pageIndex: 0,
        anchorPt: const PdfPoint(100, 700),
        contents: 'Check',
      )
      ..addStamp(
        preset: StampPreset.urgent,
        pageIndex: 0,
        anchorPt: const PdfPoint(200, 700),
      );

    expect(s().session.annotations, hasLength(2));
    expect(s().session.onPage(0), hasLength(2));
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/viewer/note_stamp_placement_test.dart`
Expected: FAIL — `addNote` is not defined

- [ ] **Step 4: Add the controller methods**

In `lib/features/viewer/annotation_providers.dart`, add to `AnnotationController`:
```dart
  /// Stages a sticky note. Empty text is refused: an icon that says nothing
  /// only clutters the page.
  void addNote({
    required int pageIndex,
    required PdfPoint anchorPt,
    required String contents,
  }) {
    if (contents.trim().isEmpty) return;

    state.session.add(
      StickyNote(
        pageIndex: pageIndex,
        anchorPt: anchorPt,
        contents: contents.trim(),
      ),
    );
    _touch();
  }

  void addStamp({
    required StampPreset preset,
    required int pageIndex,
    required PdfPoint anchorPt,
  }) {
    state.session.add(
      Stamp(preset: preset, pageIndex: pageIndex, anchorPt: anchorPt),
    );
    _touch();
  }
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/viewer/note_stamp_placement_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 6: Build the dialog, picker and surface**

`note_dialog.dart` — `Future<String?> showNoteDialog(BuildContext context, {String initial = ''})`: an `AlertDialog` with a multiline `TextField` (`maxLines: 4`), Cancel, and Save. Save returns the trimmed text; empty text keeps Save disabled with `l10n.noteEmpty` as helper text.

`stamp_picker.dart` — a `StatelessWidget` row of six `ChoiceChip`s, one per `StampPreset`, each tinted with its own `colorArgb` and labelled from l10n. Takes `selected` and `onSelected`.

`tap_placement_surface.dart` — a `ConsumerWidget`:

```dart
class TapPlacementSurface extends ConsumerWidget {
  const TapPlacementSurface({
    required this.pageRect,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.pageIndex,
    required this.onTap,
    super.key,
  });

  final Rect pageRect;
  final double pageWidthPt;
  final double pageHeightPt;
  final int pageIndex;
  final void Function(PdfPoint) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staged = ref
        .watch(annotationSessionProvider)
        .session
        .onPage(pageIndex);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => onTap(
        canvasToPdf(
          d.localPosition,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _StagedPainter(
          annotations: staged,
          pageRect: pageRect,
          pageWidthPt: pageWidthPt,
          pageHeightPt: pageHeightPt,
        ),
      ),
    );
  }
}
``` A `CustomPaint` previews staged notes and stamps on this page by converting their anchors back with `pdfToCanvas` — an icon-sized rounded square for a note, a labelled box for a stamp — so what is staged is visible before saving.

One surface serves both modes; the mode decides what `onTap` does.

- [ ] **Step 7: Add the two modes to the viewer**

In `lib/features/viewer/viewer_screen.dart`:
- extend `enum _ViewerMode` with `note` and `stamp`, and `_AnnotateTool` likewise;
- add two `PopupMenuItem`s: `l10n.noteMode` with `Icons.sticky_note_2_outlined`, `l10n.stampMode` with `Icons.approval_outlined`;
- `_enterNoteMode()` and `_enterStampMode()` each call `ref.read(annotationSessionProvider.notifier).reset()` then set the mode; the stamp mode also sets `_stampPreset = StampPreset.approved` as the default selection;
- add both to the `leading:` switch, leaving via the same discard prompt as draw mode (`l10n.drawDiscardPrompt`);
- extend `pageOverlaysBuilder` with a branch returning `TapPlacementSurface` for both modes, passing `Offset.zero & pageRect.size`. Its `onTap` opens `showNoteDialog` then calls `addNote` in note mode, or calls `addStamp` with `_stampPreset` in stamp mode;
- show a toolbar in each mode: note mode shows `l10n.notePlaceHint`, stamp mode shows a `StampPicker` bound to `_stampPreset`; both get an undo button and a pinned Save calling the existing `_saveAnnotations`.

- [ ] **Step 8: Let the edit toolbar change note text**

In `lib/features/viewer/widgets/annotation_edit_toolbar.dart`:
- when the selected annotation's `subtype` is `Text`, show an edit-text `IconButton` that opens `showNoteDialog` with the note's current text and calls `controller.restyleSelected(AnnotationStyle(colorArgb: colour, strokeWidth: width, contents: newText))`;
- disable the thickness slider when the selection is a note — a `/Text` icon has no stroke, so the control would do nothing.

- [ ] **Step 9: Verify on the simulator**

```bash
flutter build ios --simulator --debug
xcrun simctl install DFC5606D-37F0-4176-A73D-B8214C7F820F build/ios/iphonesimulator/Runner.app
xcrun simctl launch DFC5606D-37F0-4176-A73D-B8214C7F820F dev.folio.app
```

Place a note, type text, save, reopen, and confirm the icon renders. Place each of the six stamps and confirm each label is readable and not clipped. Edit a saved note's text. **Demo this on the simulator.**

Note: any `flutter test integration_test/...` run overwrites `build/ios/iphonesimulator/Runner.app` with the test harness. Rebuild before installing for manual testing or the app launches to a blank screen.

- [ ] **Step 10: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add sticky note and stamp placement modes

Both are tap-to-place: a note is a fixed-size icon and a stamp's box is
determined by its label, so there is nothing for a drag to size.

An empty note is refused rather than staged - an icon that says nothing only
clutters the page. The thickness slider is disabled for notes, because a /Text
icon has no stroke."
```

---

### Task 5: End-to-end verification and documentation

**Files:**
- Create: `integration_test/notes_stamps_flow_test.dart`
- Modify: `integration_test/all_tests.dart`, `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`

- [ ] **Step 1: Write the end-to-end flows**

`integration_test/notes_stamps_flow_test.dart` builds a real library and asserts by **rendering**:

1. a placed note draws its icon — render before and after, require more than 200 pixels to differ;
2. a placed stamp draws — require more than 500 pixels to differ;
3. **all six presets render**, looping over `StampPreset.values`, each requiring more than 500 pixels;
4. a note and a stamp saved together both appear in the bytes, and the document reopens with the right page count;
5. editing a saved note's text changes `/Contents` while its `/Rect` string is unchanged — load with `AnnotationEditRepositoryImpl`, save with `AnnotationStyle(contents: …)`, reload and compare;
6. deleting a note removes it — after deletion the render matches the original within 200 pixels;
7. the source document is byte-identical afterwards.

Register it in `integration_test/all_tests.dart`:
```dart
import 'notes_stamps_flow_test.dart' as notes_stamps_flow;
// ...
  group('notes_stamps_flow', notes_stamps_flow.main);
```

- [ ] **Step 2: Run on the iOS simulator**

```bash
flutter test integration_test/all_tests.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including every earlier suite.

Use the aggregate entrypoint, not the directory: `flutter test integration_test` reinstalls and relaunches the app once per file.

- [ ] **Step 3: Verify the stamp assertion actually bites**

Change `Stamp.widthPt` to a fixed `40` — narrow enough to clip every label — and re-run the flow file. Confirm the six-preset test still passes (a clipped label still draws pixels), then **revert** and record in `TESTING.md` that pixel-count assertions cannot detect clipping, which is why the box-sizing rule has its own unit test.

This step exists because SP-3d shipped an assertion that measured nothing; the check is cheap and the answer belongs in the docs either way.

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

- `FEATURES.md` — an SP-3e table for notes and stamps, ✅ where verified and 🟡 for Windows. State that a note carries no appearance stream and stays searchable.
- `LIMITATIONS.md` — stamps are a fixed preset set and cannot be restyled, only deleted; there are no custom or date stamps; notes are icons with popups, not text boxes on the page.
- `ARCHITECTURE.md` — why a note has no appearance stream and a stamp must have one, with the probe numbers; why the stamp box is sized from its label rather than measured; that standard-14 fonts are referenced, never embedded.
- `TESTING.md` — refresh counts and the date, and add the clipping note from Step 3.

- [ ] **Step 7: Full verification and push**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
git add -A && git commit -m "test: add end-to-end note and stamp flows and update docs

Every flow reopens the output and requires the annotation to render, including
all six stamp presets."
git push -u origin feature/sp3e-notes-and-stamps
gh pr create --base develop --title "SP-3e: sticky notes and stamps"
```

Confirm all four CI jobs pass, including `build-windows`.

---

## Definition of done

- [ ] Place, save and delete sticky notes; edit a saved note's text
- [ ] Place, save and delete all six stamp presets
- [ ] Notes carry no appearance stream; stamps carry one and render
- [ ] Stamps are labelled delete-only in Edit annotations
- [ ] Every SP-3a, SP-3b, SP-3c and SP-3d test still passes
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

**Next:** SP-3f — moving and resizing annotations.
