# SP-4a — Text Watermarks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stamp a text watermark across every page of a document.

**Architecture:** One incremental update appends a `q`/`Q`-balanced content stream to every page and overrides each page dictionary so its `/Contents` includes that stream and its `/Resources` gains a shared font and ExtGState. This is the first slice that writes page **content** rather than annotations; it needs no object layer and no new dependency, both proven on device.

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5, pdfrx 2.4.7 (PDFium), drift 2.34.3, flutter_riverpod 3.3.2.

**Spec:** `docs/superpowers/specs/2026-08-26-sp4a-watermarks-design.md`

## Global Constraints

- **Zero AI, zero paid or proprietary SDKs, no GPL/LGPL/AGPL.** No new dependencies, and **no embedded fonts** — Helvetica is referenced, never embedded.
- **Never destroy originals.** Applying a watermark writes a new document through `DocumentWriter`.
- **`PdfEngine` has no write method and must not gain one.**
- **`PdfObjectReader` handles page dictionaries and nothing else** — resolving inherited `/MediaBox` therefore lives in a sibling.
- **Never log document content, passwords, filenames or paths.** Watermark text is document content.
- **Folio stamps no `/Producer`, no `/ModDate`, and no ownership marker.**
- **A feature is not done until it has been verified by rendering.**
- Run `dart format lib test integration_test scripts` and `flutter analyze --fatal-infos` before every commit.

## Critical context the implementer will not guess

**Probed on device 2026-08-26, not assumed:** appending a content stream to `/Contents` by incremental update changed 3,075 pixels and left the original bytes byte-identical. `dart:io`'s `ZLibCodec` is available with no dependency and PDFium accepts a stream we compressed (48,000 pixels) — though this slice writes its stream **uncompressed**, because a watermark stream is a few hundred bytes and compressing it would trade clarity for nothing.

**The appended stream must be `q`/`Q` balanced.** It runs after the page's own content. An unbalanced stream leaks graphics state into everything appended after it, including a second watermark.

**`/Resources` is merged, never replaced.** Replacing a page's resources strips the fonts its own content depends on and the page renders blank. This is the same rule `withAnnots` already follows for `/Annots`.

**`/MediaBox` is inheritable.** A page dictionary may not carry one; it then inherits from its `/Pages` ancestor. Resolving that means reading a non-page object, which is past `PdfObjectReader`'s stated mandate — hence `page_geometry.dart`.

**`/Contents` arrives in three forms** — a single reference, an array, or absent — and all three must work.

## File structure

| File | Responsibility |
|---|---|
| `lib/domain/watermark/watermark.dart` | **New.** The `Watermark` model and `WatermarkRotation`. |
| `lib/domain/watermark/watermark_content.dart` | **New.** The content stream and the ExtGState dictionary. |
| `lib/domain/watermark/page_geometry.dart` | **New.** `/MediaBox` resolved through inheritance. |
| `lib/domain/annotations/pdf_object_reader.dart` | **Modify.** `withContentsAndResources`; doc comment widened to match. |
| `lib/domain/watermark/pdf_watermark_writer.dart` | **New.** One incremental update covering every page. |
| `lib/domain/repositories/watermark_repository.dart` | **New.** Interface. |
| `lib/data/repositories/watermark_repository_impl.dart` | **New.** Goes through `DocumentWriter`. |
| `lib/features/viewer/widgets/watermark_sheet.dart` | **New.** Text, size, colour, opacity, rotation, live preview. |
| `lib/features/viewer/viewer_screen.dart` | **Modify.** A Watermark entry that opens the sheet. |
| `lib/main.dart` | **Modify.** Overrides the repository provider. |

---

# Stage 1 — Drawing the mark

Ends with: a content stream that draws a watermark, and page geometry to place it.

---

### Task 1: The watermark and its content stream

**Files:**
- Create: `lib/domain/watermark/watermark.dart`, `lib/domain/watermark/watermark_content.dart`
- Test: `test/domain/watermark/watermark_content_test.dart`

**Interfaces:**
- Consumes: `pdfNumber` and `pdfString` from `pdf_appearance.dart`, `TextRect` from `pdf_types.dart`
- Produces: `enum WatermarkRotation { diagonal, horizontal }`; `Watermark({required String text, double fontSizePt, int colorArgb, double opacity, WatermarkRotation rotation})`; `String watermarkContentStream(Watermark mark, {required TextRect mediaBox})`; `String watermarkExtGState(Watermark mark)`

- [ ] **Step 1: Write the failing test**

`test/domain/watermark/watermark_content_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'package:folio/domain/watermark/watermark_content.dart';

const a4 = TextRect(left: 0, bottom: 0, right: 595, top: 842);
const draft = Watermark(text: 'DRAFT');

void main() {
  group('the stream restores what it found', () {
    // Our stream runs after the page's own content. An unbalanced stream
    // leaks graphics state into everything appended after it.
    test('is q/Q balanced', () {
      final s = watermarkContentStream(draft, mediaBox: a4);

      expect(RegExp(r'^q$', multiLine: true).allMatches(s).length, 1);
      expect(RegExp(r'^Q$', multiLine: true).allMatches(s).length, 1);
      expect(s.trimLeft().startsWith('q'), isTrue);
      expect(s.trimRight().endsWith('Q'), isTrue);
    });
  });

  group('what it draws', () {
    test('draws the text', () {
      expect(watermarkContentStream(draft, mediaBox: a4), contains('(DRAFT)'));
      expect(watermarkContentStream(draft, mediaBox: a4), contains('Tj'));
    });

    test('uses the named font resource', () {
      expect(watermarkContentStream(draft, mediaBox: a4), contains('/WMF1'));
    });

    // Opacity belongs in an ExtGState. Faking it with a pale fill colour
    // would look wrong over dark content and could not be undone by a viewer.
    test('applies opacity through the ExtGState, not the fill colour', () {
      final s = watermarkContentStream(draft, mediaBox: a4);

      expect(s, contains('/WMGS gs'));
      expect(watermarkExtGState(draft), contains('/ca 0.3'));
      expect(watermarkExtGState(draft), contains('/CA 0.3'));
    });

    test('escapes parentheses in the text', () {
      const tricky = Watermark(text: 'see (b)');
      expect(
        watermarkContentStream(tricky, mediaBox: a4),
        contains(r'(see \(b\))'),
      );
    });
  });

  group('placement', () {
    test('rotates about the page centre when diagonal', () {
      final s = watermarkContentStream(draft, mediaBox: a4);

      // Translate to the centre, rotate, translate back.
      expect(s, contains('297.5 421 cm'));
      expect(s, contains('cm'));
    });

    test('emits no rotation when horizontal', () {
      const flat = Watermark(
        text: 'DRAFT',
        rotation: WatermarkRotation.horizontal,
      );
      final s = watermarkContentStream(flat, mediaBox: a4);

      // One cm for the centring translate, none for a rotation.
      expect(RegExp(r'\bcm\b').allMatches(s).length, 1);
    });

    // A page is not always A4, and a watermark centred on the wrong size
    // lands off the paper.
    test('centres on the page it is given', () {
      const wide = TextRect(left: 0, bottom: 0, right: 1000, top: 500);
      final s = watermarkContentStream(draft, mediaBox: wide);

      expect(s, contains('500 250 cm'));
    });

    test('honours a non-zero MediaBox origin', () {
      const offset = TextRect(left: 100, bottom: 100, right: 700, top: 900);
      final s = watermarkContentStream(draft, mediaBox: offset);

      expect(s, contains('400 500 cm'));
    });
  });

  group('style', () {
    test('emits the colour as a fill colour', () {
      const red = Watermark(text: 'DRAFT', colorArgb: 0xFFFF0000);
      expect(watermarkContentStream(red, mediaBox: a4), contains('1 0 0 rg'));
    });

    test('emits the font size', () {
      const big = Watermark(text: 'DRAFT', fontSizePt: 72);
      expect(
        watermarkContentStream(big, mediaBox: a4),
        contains('/WMF1 72 Tf'),
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/watermark/watermark_content_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Write the model**

`lib/domain/watermark/watermark.dart`:
```dart
enum WatermarkRotation { diagonal, horizontal }

/// A text mark stamped across every page of a document.
///
/// This is page content, not an annotation: an annotation would be a stamp,
/// which SP-3e already ships and which any viewer can delete. Being part of
/// the page is the point.
class Watermark {
  const Watermark({
    required this.text,
    this.fontSizePt = 48,
    this.colorArgb = 0xFF9E9E9E,
    this.opacity = 0.3,
    this.rotation = WatermarkRotation.diagonal,
  });

  final String text;
  final double fontSizePt;
  final int colorArgb;

  /// 0 is invisible, 1 is opaque.
  final double opacity;

  final WatermarkRotation rotation;
}
```

- [ ] **Step 4: Write the content stream**

`lib/domain/watermark/watermark_content.dart`:
```dart
import 'dart:math' as math;

import 'package:folio/domain/annotations/pdf_appearance.dart'
    show pdfNumber, pdfString;
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// The resource names the watermark introduces into a page's /Resources.
///
/// Prefixed so they cannot collide with names the page's own content already
/// uses - a page with its own /F1 would otherwise start drawing in our font.
const watermarkFontName = 'WMF1';
const watermarkGStateName = 'WMGS';

/// Rough advance width of mixed-case Helvetica, used only to centre the text.
/// Carrying a metrics table for a font we do not embed is not worth it.
const _averageGlyphWidth = 0.6;

/// Content drawing [mark] centred on a page of [mediaBox].
///
/// Wrapped in q ... Q: this runs after the page's own content, and an
/// unbalanced stream leaks graphics state into everything appended after it.
String watermarkContentStream(Watermark mark, {required TextRect mediaBox}) {
  final centreX = (mediaBox.left + mediaBox.right) / 2;
  final centreY = (mediaBox.bottom + mediaBox.top) / 2;

  final width = mark.text.length * mark.fontSizePt * _averageGlyphWidth;
  // Text is drawn from its baseline, so drop by roughly a third of the size
  // to sit the visual centre of the glyphs on the page centre.
  final offsetX = -width / 2;
  final offsetY = -mark.fontSizePt / 3;

  String channel(int shift) =>
      pdfNumber(((mark.colorArgb >> shift) & 0xFF) / 255);

  final buffer = StringBuffer()
    ..writeln('q')
    ..writeln('/$watermarkGStateName gs')
    ..writeln('${channel(16)} ${channel(8)} ${channel(0)} rg')
    ..writeln('1 0 0 1 ${pdfNumber(centreX)} ${pdfNumber(centreY)} cm');

  if (mark.rotation == WatermarkRotation.diagonal) {
    // Roughly the diagonal of a portrait page.
    const radians = 55 * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    // Negate the VALUE, not the formatted string: '-${pdfNumber(sin)}' yields
    // '--0.5' the moment sin is negative.
    buffer.writeln(
      '${pdfNumber(cos)} ${pdfNumber(sin)} '
      '${pdfNumber(-sin)} ${pdfNumber(cos)} 0 0 cm',
    );
  }

  buffer
    ..writeln('BT')
    ..writeln('/$watermarkFontName ${pdfNumber(mark.fontSizePt)} Tf')
    ..writeln('${pdfNumber(offsetX)} ${pdfNumber(offsetY)} Td')
    ..writeln('${pdfString(mark.text)} Tj')
    ..writeln('ET')
    ..write('Q');

  return buffer.toString();
}

/// The graphics state carrying the watermark's opacity.
///
/// Opacity belongs here rather than in a pale fill colour: a pale colour looks
/// wrong over dark content, and it is not something a viewer can reason about.
String watermarkExtGState(Watermark mark) =>
    '<< /Type /ExtGState /ca ${pdfNumber(mark.opacity)} '
    '/CA ${pdfNumber(mark.opacity)} >>';
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/domain/watermark/watermark_content_test.dart`
Expected: PASS — 11 tests

- [ ] **Step 6: Mutation-test the balance and the opacity**

Remove the `..write('Q')` line. Run the test file.

Expected: `is q/Q balanced` FAILS. Revert.

Then change `/$watermarkGStateName gs` to a pale fill instead — delete that line and multiply each colour channel by the opacity. Run again.

Expected: `applies opacity through the ExtGState, not the fill colour` FAILS. Revert.

- [ ] **Step 7: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: draw a text watermark as page content

Wrapped in q ... Q because it runs after the page's own content: an unbalanced
stream leaks graphics state into everything appended after it.

Opacity goes in an ExtGState rather than a pale fill colour, which would look
wrong over dark content. Resource names are prefixed so they cannot collide
with names the page's own content already uses."
```

---

### Task 2: Page geometry

**Files:**
- Create: `lib/domain/watermark/page_geometry.dart`
- Test: `test/domain/watermark/page_geometry_test.dart`

**Interfaces:**
- Consumes: `PdfObjectIndex`, `PdfObjectReader`, `PdfPageObject`, `TextRect`
- Produces: `TextRect mediaBoxOf(PdfObjectIndex index, PdfPageObject page)`

- [ ] **Step 1: Write the failing test**

`test/domain/watermark/page_geometry_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/watermark/page_geometry.dart';

ParsedPage parse(String pdf) {
  final index = PdfObjectIndex.parse(pdf);
  final page = PdfObjectReader.parse(pdf).pageAt(0)!;
  return (index: index, page: page);
}

typedef ParsedPage = ({PdfObjectIndex index, PdfPageObject page});

void main() {
  test('reads a /MediaBox on the page itself', () {
    const pdf =
        '%PDF-1.4\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\n'
        'endobj\n';
    final p = parse(pdf);

    final box = mediaBoxOf(p.index, p.page);
    expect(box.right, 595);
    expect(box.top, 842);
  });

  // /MediaBox is inheritable. Reading only the page dictionary centres a
  // watermark off-page on exactly the documents that rely on inheritance.
  test('inherits /MediaBox from the /Pages node', () {
    const pdf =
        '%PDF-1.4\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 '
        '/MediaBox [0 0 612 792] >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
    final p = parse(pdf);

    final box = mediaBoxOf(p.index, p.page);
    expect(box.right, 612);
    expect(box.top, 792);
  });

  test('the page own value wins over the inherited one', () {
    const pdf =
        '%PDF-1.4\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 '
        '/MediaBox [0 0 612 792] >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\n'
        'endobj\n';
    final p = parse(pdf);

    expect(mediaBoxOf(p.index, p.page).right, 595);
  });

  test('follows more than one level of /Parent', () {
    const pdf =
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Pages /Kids [2 0 R] /Count 1 '
        '/MediaBox [0 0 400 400] >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Parent 1 0 R /Kids [3 0 R] /Count 1 >>\n'
        'endobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
    final p = parse(pdf);

    expect(mediaBoxOf(p.index, p.page).right, 400);
  });

  test('honours a non-zero origin', () {
    const pdf =
        '%PDF-1.4\n'
        '3 0 obj\n<< /Type /Page /MediaBox [10 20 610 812] >>\nendobj\n';
    final p = parse(pdf);

    final box = mediaBoxOf(p.index, p.page);
    expect(box.left, 10);
    expect(box.bottom, 20);
  });

  // A document this malformed will still render; refusing to save because we
  // could not find a page size would help nobody.
  test('falls back to US Letter when there is no /MediaBox anywhere', () {
    const pdf = '%PDF-1.4\n3 0 obj\n<< /Type /Page >>\nendobj\n';
    final p = parse(pdf);

    final box = mediaBoxOf(p.index, p.page);
    expect(box.right, 612);
    expect(box.top, 792);
  });

  // A /Parent cycle in a damaged document must not hang the app.
  test('a /Parent cycle terminates', () {
    const pdf =
        '%PDF-1.4\n'
        '2 0 obj\n<< /Type /Pages /Parent 3 0 R /Kids [3 0 R] >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
    final p = parse(pdf);

    expect(mediaBoxOf(p.index, p.page).right, 612);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/watermark/page_geometry_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/watermark/page_geometry.dart`:
```dart
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/engine/pdf_types.dart';

/// US Letter, used when a document declares no page size anywhere.
const _fallback = TextRect(left: 0, bottom: 0, right: 612, top: 792);

/// How far up the /Parent chain to look before giving up. A damaged document
/// can contain a cycle, and hanging is worse than guessing a page size.
const _maxDepth = 32;

/// The page's `/MediaBox`, resolved through inheritance.
///
/// `/MediaBox` is an inheritable attribute: a page dictionary need not carry
/// one, in which case it comes from an ancestor `/Pages` node. Reading only
/// the page's own dictionary centres a watermark off-page on exactly the
/// documents that rely on inheritance.
///
/// This lives outside `PdfObjectReader` on purpose. Following `/Parent` means
/// reading a node that is not a page dictionary, and that reader's own
/// documentation says a caller needing more than page dictionaries should
/// reconsider scope rather than grow the file.
TextRect mediaBoxOf(PdfObjectIndex index, PdfPageObject page) {
  var dict = page.rawDictionary;

  for (var depth = 0; depth < _maxDepth; depth++) {
    final box = _boxIn(dict);
    if (box != null) return box;

    final parent = RegExp(r'/Parent\s+(\d+)\s+\d+\s+R').firstMatch(dict);
    if (parent == null) break;

    final next = index.bodyOf(int.parse(parent.group(1)!));
    if (next == null) break;
    dict = next;
  }

  return _fallback;
}

TextRect? _boxIn(String dict) {
  final match = RegExp(r'/MediaBox\s*\[([^\]]*)\]').firstMatch(dict);
  if (match == null) return null;

  final numbers = RegExp(r'-?\d+(?:\.\d+)?')
      .allMatches(match.group(1)!)
      .map((m) => double.parse(m.group(0)!))
      .toList();
  if (numbers.length < 4) return null;

  return TextRect(
    left: numbers[0],
    bottom: numbers[1],
    right: numbers[2],
    top: numbers[3],
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/watermark/page_geometry_test.dart`
Expected: PASS — 7 tests

- [ ] **Step 5: Mutation-test inheritance and the cycle guard**

Delete the `/Parent` lookup so only the page's own dictionary is read. Run the test file.

Expected: `inherits /MediaBox from the /Pages node` and `follows more than one level of /Parent` both FAIL. Revert.

Then change `depth < _maxDepth` to `true`. Run again.

Expected: `a /Parent cycle terminates` hangs until the test times out rather than passing. Revert. A hang is the failure — do not leave it running.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: resolve a page's /MediaBox through inheritance

/MediaBox is inheritable, so reading only the page dictionary centres a
watermark off-page on documents that rely on it. Lives outside PdfObjectReader
because following /Parent means reading a node that is not a page dictionary,
and that file's documentation says to reconsider scope rather than grow it.

Bounded depth: a damaged document can contain a /Parent cycle, and hanging is
worse than guessing a page size."
```

---

# Stage 2 — Writing it into the document

Ends with: a watermarked PDF that renders on every page.

---

### Task 3: The watermark writer

**Files:**
- Modify: `lib/domain/annotations/pdf_object_reader.dart`
- Create: `lib/domain/watermark/pdf_watermark_writer.dart`
- Test: `test/domain/annotations/pdf_object_reader_test.dart`, `test/domain/watermark/pdf_watermark_writer_test.dart`

**Interfaces:**
- Consumes: `watermarkContentStream`, `watermarkExtGState`, `watermarkFontName`, `watermarkGStateName` (Task 1), `mediaBoxOf` (Task 2), `helveticaFontObject` from `stamp_appearance.dart`
- Produces: `String PdfObjectReader.withContentsAndResources(PdfPageObject page, {required int contentObjectNumber, required int fontObjectNumber, required int extGStateObjectNumber})`; `Uint8List writeWatermark(Uint8List pdf, Watermark mark)`

- [ ] **Step 1: Add the failing reader tests**

Append to `test/domain/annotations/pdf_object_reader_test.dart`:
```dart
  group('withContentsAndResources', () {
    PdfPageObject pageOf(String dict) =>
        PdfObjectReader.parse(pdfWith(dict)).pageAt(0)!;

    String rewrite(String dict) {
      final reader = PdfObjectReader.parse(pdfWith(dict));
      return reader.withContentsAndResources(
        reader.pageAt(0)!,
        contentObjectNumber: 20,
        fontObjectNumber: 21,
        extGStateObjectNumber: 22,
      );
    }

    test('a single /Contents reference becomes an array', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>',
      );
      expect(out, contains('/Contents [4 0 R 20 0 R]'));
    });

    test('an existing /Contents array is appended to', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R /Contents [4 0 R 5 0 R] >>',
      );
      expect(out, contains('/Contents [4 0 R 5 0 R 20 0 R]'));
    });

    test('a page with no /Contents gains one', () {
      final out = rewrite('<< /Type /Page /Parent 2 0 R >>');
      expect(out, contains('/Contents [20 0 R]'));
    });

    test('a page with no /Resources gains them', () {
      final out = rewrite('<< /Type /Page /Parent 2 0 R >>');

      expect(out, contains('/WMF1 21 0 R'));
      expect(out, contains('/WMGS 22 0 R'));
    });

    // Replacing a page's /Resources strips the fonts its own content depends
    // on, and the page renders blank.
    test('existing /Resources survive the merge', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R '
        '/Resources << /Font << /F1 9 0 R >> >> >>',
      );

      expect(out, contains('/F1 9 0 R'), reason: 'the page own font');
      expect(out, contains('/WMF1 21 0 R'), reason: 'ours');
    });

    test('an existing /ExtGState entry survives too', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R '
        '/Resources << /ExtGState << /GS0 8 0 R >> >> >>',
      );

      expect(out, contains('/GS0 8 0 R'));
      expect(out, contains('/WMGS 22 0 R'));
    });

    test('other page keys are left alone', () {
      final out = rewrite(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Rotate 90 /Contents 4 0 R >>',
      );

      expect(out, contains('/MediaBox [0 0 595 842]'));
      expect(out, contains('/Rotate 90'));
    });

    test('pageOf reads the dictionary it was given', () {
      expect(
        pageOf('<< /Type /Page /Parent 2 0 R >>').rawDictionary,
        contains('/Type /Page'),
      );
    });
  });
```

`pdfWith` already exists at the top of that file.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_object_reader_test.dart`
Expected: FAIL — `withContentsAndResources` is not defined

- [ ] **Step 3: Implement the re-emission**

In `lib/domain/annotations/pdf_object_reader.dart`, widen the class doc comment's first line to name both operations:
```dart
/// A deliberately minimal PDF reader: it finds page dictionaries and re-emits
/// them with an added `/Annots`, or with an added `/Contents` entry and merged
/// `/Resources`, and does nothing else.
```

Then add:
```dart
  /// Re-emits [page]'s dictionary with a watermark's content stream appended
  /// to `/Contents` and its resources merged into `/Resources`.
  ///
  /// `/Contents` may be a single reference, an array, or absent, and all three
  /// occur in real documents. `/Resources` is MERGED: replacing it strips the
  /// fonts the page's own content depends on, and the page renders blank.
  String withContentsAndResources(
    PdfPageObject page, {
    required int contentObjectNumber,
    required int fontObjectNumber,
    required int extGStateObjectNumber,
  }) {
    var body = page.rawDictionary;
    body = body.substring(2, body.length - 2).trim();

    final contents = RegExp(r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)')
        .firstMatch(body);
    final existing = contents == null
        ? ''
        : contents.group(1)!.startsWith('[')
        ? contents.group(1)!.substring(1, contents.group(1)!.length - 1).trim()
        : contents.group(1)!.trim();

    final merged = existing.isEmpty
        ? '/Contents [$contentObjectNumber 0 R]'
        : '/Contents [$existing $contentObjectNumber 0 R]';

    body = contents == null
        ? '$body $merged'
        : body.replaceRange(contents.start, contents.end, merged);

    body = _withResources(body, fontObjectNumber, extGStateObjectNumber);
    return '<< $body >>';
  }

  /// Merges the watermark's font and graphics state into `/Resources`,
  /// preserving whatever is already there.
  static String _withResources(String body, int fontNum, int gsNum) {
    final font = '/$watermarkFontName $fontNum 0 R';
    final gs = '/$watermarkGStateName $gsNum 0 R';

    final resources = RegExp(r'/Resources\s*<<').firstMatch(body);
    if (resources == null) {
      return '$body /Resources << /Font << $font >> /ExtGState << $gs >> >>';
    }

    final open = body.indexOf('<<', resources.start + '/Resources'.length);
    final close = PdfObjectIndex.matchingClose(body, open);
    if (close < 0) {
      return '$body /Resources << /Font << $font >> /ExtGState << $gs >> >>';
    }

    var inner = body.substring(open + 2, close).trim();
    inner = _mergeSub(inner, 'Font', font);
    inner = _mergeSub(inner, 'ExtGState', gs);

    return body.replaceRange(open, close + 2, '<< $inner >>');
  }

  /// Adds [entry] to the named sub-dictionary, creating it if absent.
  static String _mergeSub(String inner, String key, String entry) {
    final match = RegExp('/$key\\s*<<').firstMatch(inner);
    if (match == null) return '$inner /$key << $entry >>';

    final open = inner.indexOf('<<', match.start + key.length);
    final close = PdfObjectIndex.matchingClose(inner, open);
    if (close < 0) return '$inner /$key << $entry >>';

    final existing = inner.substring(open + 2, close).trim();
    return inner.replaceRange(open, close + 2, '<< $existing $entry >>');
  }
```

Add `import 'package:folio/domain/watermark/watermark_content.dart' show watermarkFontName, watermarkGStateName;`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_object_reader_test.dart`
Expected: PASS — the existing tests plus 8 new.

- [ ] **Step 5: Write the failing writer test**

`test/domain/watermark/pdf_watermark_writer_test.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/watermark/pdf_watermark_writer.dart';
import 'package:folio/domain/watermark/watermark.dart';

Uint8List twoPages() => Uint8List.fromList(
  latin1.encode(
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n'
    '4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n'
    '5 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>\nendobj\n'
    '6 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n'
    'xref\n0 7\n0000000000 65535 f \n'
    'trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
  ),
);

const draft = Watermark(text: 'DRAFT');

void main() {
  test('the original bytes are still present, untouched', () {
    final original = twoPages();
    final out = writeWatermark(original, draft);

    expect(out.sublist(0, original.length), original);
  });

  // A watermark marks a document. On page one only it says nothing.
  test('every page is watermarked', () {
    final text = latin1.decode(writeWatermark(twoPages(), draft));

    expect(RegExp(r'\(DRAFT\) Tj').allMatches(text).length, 2);
    expect(text, contains('3 0 obj'));
    expect(text, contains('5 0 obj'));
  });

  test('the font and graphics state are emitted once, not per page', () {
    final text = latin1.decode(writeWatermark(twoPages(), draft));

    expect(RegExp(r'/BaseFont /Helvetica').allMatches(text).length, 1);
    expect(RegExp(r'/Type /ExtGState').allMatches(text).length, 1);
  });

  test('each page references the watermark stream', () {
    final text = latin1.decode(writeWatermark(twoPages(), draft));
    expect(RegExp(r'/Contents \[\d+ 0 R \d+ 0 R\]').allMatches(text).length, 2);
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
      () => writeWatermark(modern, draft),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  test('empty text is refused rather than stamping nothing', () {
    expect(
      () => writeWatermark(twoPages(), const Watermark(text: '   ')),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/domain/watermark/pdf_watermark_writer_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 7: Implement the writer**

`lib/domain/watermark/pdf_watermark_writer.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_object_index.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/stamp_appearance.dart'
    show helveticaFontObject;
import 'package:folio/domain/watermark/page_geometry.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'package:folio/domain/watermark/watermark_content.dart';

/// Stamps [mark] across every page by appending a PDF incremental update.
///
/// The original bytes are never rewritten: a content stream per page, one
/// shared font and graphics state, and an overridden page dictionary each.
Uint8List writeWatermark(Uint8List pdf, Watermark mark) {
  if (mark.text.trim().isEmpty) {
    throw ArgumentError.value(mark.text, 'text', 'a watermark needs text');
  }

  final text = latin1.decode(pdf, allowInvalid: true);
  final reader = PdfObjectReader.parse(text);
  final index = PdfObjectIndex.parse(text);

  if (reader.usesXrefStream) {
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

  // One font and one graphics state for the whole document, not one per page.
  final fontNum = nextObj++;
  emit(fontNum, helveticaFontObject());
  final gsNum = nextObj++;
  emit(gsNum, watermarkExtGState(mark));

  for (var pageIndex = 0; ; pageIndex++) {
    final page = reader.pageAt(pageIndex);
    if (page == null) break;

    // Per page: a page may be a different size from its neighbours, and a
    // watermark centred on the wrong one lands off the paper.
    final stream = watermarkContentStream(
      mark,
      mediaBox: mediaBoxOf(index, page),
    );

    final contentNum = nextObj++;
    emit(contentNum, '<< /Length ${stream.length} >>\nstream\n$stream\nendstream');

    emit(
      page.objectNumber,
      reader.withContentsAndResources(
        page,
        contentObjectNumber: contentNum,
        fontObjectNumber: fontNum,
        extGStateObjectNumber: gsNum,
      ),
    );
  }

  // One xref subsection per object: always valid, and avoids having to detect
  // runs of consecutive numbers.
  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  for (final n in offsets.keys.toList()..sort()) {
    buffer.writeln('$n 1');
    buffer.writeln('${offsets[n]!.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer.writeln('trailer');

  // Carry /Info forward: the newest trailer wins, and one without it discards
  // the document's title and author.
  final info = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  final infoEntry = info.isEmpty
      ? ''
      : ' /Info ${info.last.group(1)} ${info.last.group(2)} R';

  buffer.writeln(
    '<< /Size $nextObj /Root ${root.group(1)} ${root.group(2)} R'
    '$infoEntry /Prev $prevOffset >>',
  );
  buffer.writeln('startxref');
  buffer.writeln('$xrefOffset');
  buffer.write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}
```

- [ ] **Step 8: Run to verify it passes**

Run: `dart format lib test && flutter analyze --fatal-infos && flutter test`
Expected: all pass, including every earlier suite.

- [ ] **Step 9: Mutation-test the resource merge and the per-page loop**

In `_withResources`, replace the merge with a wholesale replacement: return `'$body /Resources << /Font << $font >> /ExtGState << $gs >> >>'` unconditionally. Run `flutter test test/domain/annotations/pdf_object_reader_test.dart`.

Expected: `existing /Resources survive the merge` and `an existing /ExtGState entry survives too` both FAIL. Revert.

Then in the writer, `break` after the first page. Run the writer test file.

Expected: `every page is watermarked` FAILS with one `(DRAFT) Tj` instead of two. Revert.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: write a text watermark onto every page

One incremental update: a content stream per page, one shared font and
graphics state for the document, and an overridden page dictionary each.

/Resources is merged rather than replaced - replacing strips the fonts the
page's own content depends on and the page renders blank. /Contents is handled
as a single reference, an array, or absent, all of which occur in real files.

The page size is resolved per page: a watermark centred on the wrong one lands
off the paper."
```

---

# Stage 3 — Applying it, and verification

Ends with: a watermark applied from the app and proven by rendering.

---

### Task 4: Repository, UI, verification and docs

**Files:**
- Create: `lib/domain/repositories/watermark_repository.dart`, `lib/data/repositories/watermark_repository_impl.dart`, `lib/features/viewer/widgets/watermark_sheet.dart`, `integration_test/watermark_flow_test.dart`
- Modify: `lib/features/viewer/viewer_screen.dart`, `lib/main.dart`, `lib/l10n/app_en.arb`, `integration_test/all_tests.dart`, `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`
- Test: `test/data/repositories/watermark_repository_test.dart`

**Interfaces:**
- Consumes: `writeWatermark` (Task 3), `DocumentWriter`, `LibraryRepository`, `PdfMetadata`
- Produces: `WatermarkRepository.apply(int documentId, Watermark mark)` returning `Future<LibraryDocument>`; `watermarkRepositoryProvider`

- [ ] **Step 1: Add the strings**

Append to `lib/l10n/app_en.arb`:
```json
{
  "watermarkMode": "Watermark",
  "watermarkText": "Watermark text",
  "watermarkHint": "DRAFT, CONFIDENTIAL…",
  "watermarkSize": "Size",
  "watermarkOpacity": "Opacity",
  "watermarkDiagonal": "Diagonal",
  "watermarkHorizontal": "Horizontal",
  "watermarkApply": "Apply to every page",
  "watermarkApplied": "Watermarked {name}",
  "@watermarkApplied": { "placeholders": { "name": { "type": "String" } } },
  "watermarkEmpty": "A watermark needs some text."
}
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing repository test**

`test/data/repositories/watermark_repository_test.dart`:
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
import 'package:folio/data/repositories/watermark_repository_impl.dart';
import 'package:folio/domain/watermark/watermark.dart';

const onePage =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 '
    '/MediaBox [0 0 595 842] >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n'
    '4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n'
    'xref\n0 5\n0000000000 65535 f \n'
    'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n';

void main() {
  late Directory root;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late WatermarkRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wm');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    subject = WatermarkRepositoryImpl(
      library: library,
      documents: DocumentWriter(
        library: library,
        writer: SafeFileWriter(),
        libraryRoot: root,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<int> seed() async {
    final f = File('${root.path}/in.pdf')
      ..writeAsBytesSync(Uint8List.fromList(onePage.codeUnits));
    return (await library.importFile(f.path, displayName: 'Deed.pdf')).id;
  }

  test('produces a new document', () async {
    final id = await seed();

    final out = await subject.apply(id, const Watermark(text: 'DRAFT'));

    expect(out.id, isNot(id));
    expect(await library.all(), hasLength(2));
  });

  // Watermarking is not an edit in place, whatever the document's provenance.
  test('the source document is byte-identical afterwards', () async {
    final id = await seed();
    final src = (await library.all()).firstWhere((d) => d.id == id);
    final path = await library.resolveReadablePath(src);
    final before = await File(path).readAsBytes();

    await subject.apply(id, const Watermark(text: 'DRAFT'));

    expect(await File(path).readAsBytes(), before);
  });

  test('the watermark text reaches the new document', () async {
    final id = await seed();
    final out = await subject.apply(id, const Watermark(text: 'DRAFT'));

    final text = await File(
      await library.resolveReadablePath(out),
    ).readAsString();
    expect(text, contains('(DRAFT) Tj'));
  });

  test('empty text is rejected before anything is written', () async {
    final id = await seed();

    await expectLater(
      subject.apply(id, const Watermark(text: '  ')),
      throwsA(isA<ArgumentError>()),
    );
    expect(await library.all(), hasLength(1));
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/data/repositories/watermark_repository_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Implement the repository**

`lib/domain/repositories/watermark_repository.dart`:
```dart
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// Stamps a watermark across every page, into a new document.
abstract interface class WatermarkRepository {
  Future<LibraryDocument> apply(int documentId, Watermark mark);
}
```

`lib/data/repositories/watermark_repository_impl.dart`:
```dart
import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/repositories/watermark_repository.dart';
import 'package:folio/domain/services/edited_name.dart';
import 'package:folio/domain/watermark/pdf_watermark_writer.dart';
import 'package:folio/domain/watermark/watermark.dart';

class WatermarkRepositoryImpl implements WatermarkRepository {
  WatermarkRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<LibraryDocument> apply(int documentId, Watermark mark) async {
    final doc = (await _library.all()).firstWhere((d) => d.id == documentId);
    final bytes = await File(
      await _library.resolveReadablePath(doc),
    ).readAsBytes();

    // Throws ArgumentError on empty text before anything is written.
    final marked = writeWatermark(bytes, mark);

    // Metadata is re-read from the source so the new document inherits it,
    // exactly as every other write path does.
    return _documents.store(
      marked,
      editedName(doc.displayName),
      metadata: PdfMetadata.readFrom(bytes),
    );
  }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/data/repositories/watermark_repository_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 6: Build the sheet and wire it up**

`lib/features/viewer/widgets/watermark_sheet.dart` — a `ConsumerStatefulWidget` shown by `showModalBottomSheet`, holding the working `Watermark`:

- a `TextField` for the text, with `l10n.watermarkEmpty` as helper text while it is blank;
- a size `Slider` from 12 to 144, an opacity `Slider` from 0.05 to 1, the five shared `drawingColours` swatches, and a diagonal/horizontal `SegmentedButton`;
- a live preview: a `SizedBox` with an A4 aspect ratio containing a `CustomPaint` that draws the text rotated and faded the same way the content stream will, so what is shown matches what is written;
- a pinned **Apply to every page** button, disabled while the text is blank, that pops the sheet returning the `Watermark`.

In `lib/features/viewer/viewer_screen.dart`, add a **Watermark** entry to the Annotate popup menu using `Icons.branding_watermark_outlined` and `l10n.watermarkMode`. Selecting it shows the sheet; if it returns a `Watermark`, call `watermarkRepositoryProvider.apply(widget.document.id, mark)`, refresh the library, re-resolve `_path` so the viewer shows the result, and show `l10n.watermarkApplied`. Wrap in the same `on AppFailure` handling `_saveAnnotations` uses.

In `lib/main.dart`, construct `WatermarkRepositoryImpl(library: library, documents: documentWriter)` and add `watermarkRepositoryProvider.overrideWithValue(...)` to the `ProviderScope` overrides. Declare the provider in `lib/features/viewer/watermark_providers.dart` following the pattern of `annotationEditRepositoryProvider`.

- [ ] **Step 7: Write the end-to-end flows**

`integration_test/watermark_flow_test.dart` carries `@Timeout(Duration(minutes: 5))` and asserts by **rendering**:

1. a watermark draws on page 0 — render before and after, require more than 500 pixels to differ;
2. **it draws on the last page too**, rendering page 2 of the three-page fixture — the assertion that catches a writer that stops after page one;
3. the document still opens with the same page count;
4. the source document's SHA-256 is unchanged;
5. metadata survives, so SP-2b has not regressed;
6. the page's own text is still extractable afterwards — a watermark that corrupted the content stream would break extraction, and `q`/`Q` balance is what prevents it.

Register it in `integration_test/all_tests.dart`:
```dart
import 'watermark_flow_test.dart' as watermark_flow;
// ...
  group('watermark_flow', watermark_flow.main);
```

- [ ] **Step 8: Run on the iOS simulator**

```bash
flutter test integration_test/all_tests.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including every earlier suite.

Use the aggregate entrypoint, not the directory: `flutter test integration_test` reinstalls and relaunches the app once per file.

- [ ] **Step 9: Confirm the last-page assertion bites**

In the writer, `break` after the first page, then re-run the flow file.

Expected: `it draws on the last page too` FAILS. Revert. If it passes, the assertion is measuring nothing and must be strengthened before this slice ships — three earlier slices shipped assertions that did exactly that.

- [ ] **Step 10: Run on the Android emulator**

```bash
flutter emulators --launch pixel_api35
flutter test integration_test/all_tests.dart -d emulator-5554
```

Expected: all pass. No Android claim before this.

- [ ] **Step 11: Verify on the simulator by hand**

```bash
flutter build ios --simulator --debug
xcrun simctl install DFC5606D-37F0-4176-A73D-B8214C7F820F build/ios/iphonesimulator/Runner.app
xcrun simctl launch DFC5606D-37F0-4176-A73D-B8214C7F820F dev.folio.app
```

Apply a diagonal DRAFT watermark, confirm it appears on every page and that the page's own text is still readable through it. Try a horizontal one and a low opacity. **Demo this on the simulator.**

Note: any `flutter test integration_test/...` run overwrites `build/ios/iphonesimulator/Runner.app` with the test harness. Rebuild before installing for manual testing or the app launches to a blank screen.

- [ ] **Step 12: Verify the architectural guards still hold**

```bash
grep -nE "^\s+Future<.*> (write|save|export|materialise)" lib/domain/engine/pdf_engine.dart
```

Expected: no matches.

- [ ] **Step 13: Update the documentation**

- `FEATURES.md` — an SP-4a table for watermarks, ✅ where verified and 🟡 for Windows. Note that it applies to every page and is part of the page, not an annotation.
- `LIMITATIONS.md` — text only, no images; every page, no ranges; a watermark cannot be removed once applied, because it is page content; and a `Tj`-drawn watermark joins the page's text layer, so search finds it on every page.
- `ARCHITECTURE.md` — that this is the first slice writing page content; why the stream is `q`/`Q` balanced; why `/Resources` is merged; why `/MediaBox` resolution lives outside `PdfObjectReader`; and the probe result that compression and encryption cannot be done by appending.
- `TESTING.md` — refresh counts and the date.

- [ ] **Step 14: Full verification and push**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
git add -A && git commit -m "feat: apply a text watermark from the viewer

Every flow reopens the output and requires the watermark to render, including
on the last page - the assertion that catches a writer stopping after page one."
git push -u origin feature/sp4a-watermarks
gh pr create --base develop --title "SP-4a: text watermarks"
```

Confirm all four CI jobs pass, including `build-windows`.

---

## Definition of done

- [ ] Apply a text watermark to every page with size, colour, opacity, rotation
- [ ] `/Contents` handled as a ref, an array, and absent
- [ ] `/Resources` merged, proven by mutation
- [ ] Inherited `/MediaBox` resolved; a `/Parent` cycle terminates
- [ ] The appended stream is `q`/`Q` balanced, proven by mutation
- [ ] Source documents byte-identical; metadata survives
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

**Next:** the object-layer decision — a hand-written Dart object model versus cross-compiled qpdf — which unblocks compression, encryption and redaction together. That is a spike, not a feature slice.
