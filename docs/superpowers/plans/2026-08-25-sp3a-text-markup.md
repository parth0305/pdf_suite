# SP-3a Text Markup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user highlight, underline or strike through selected text, and save that markup into the PDF so any viewer can see it.

**Architecture:** Markup is **staged** — an `AnnotationSession` holds pending `TextMarkup` values with a command stack, all pure Dart. Saving materialises them through a **PDF incremental update**: new annotation objects, an overridden page dictionary carrying `/Annots`, a new xref section and a trailer chaining to the previous one. `PdfEngine` is untouched and stays read-only.

**Tech Stack:** Flutter 3.41.9 · Dart 3.11.5 · pdfrx 2.4.7 · flutter_riverpod 3.3.2 · drift 2.34.3 — **no new dependencies**.

**Spec:** `docs/superpowers/specs/2026-08-25-sp3a-text-markup-design.md`

## Global Constraints

- **`PdfEngine` must not gain a write, save, or export method.** All writing goes through the annotation writer. Definition-of-Done checks this.
- **Zero AI. Zero network.** `test/offline_guarantee_test.dart` fails the build on a networking dependency, a network API in `lib/`, the Android `INTERNET` permission, or the macOS `network.client` entitlement.
- **No new dependencies.** SP-3a needs none. Any addition must be MIT/BSD/Apache-2.0 and recorded in `docs/THIRD_PARTY_LICENSES.md` in the same commit.
- **Originals are never modified.** Saving produces a **new** library document; the source stays byte-identical, asserted by SHA-256.
- **Metadata must survive.** SP-2b fixed silent metadata loss. Any new save path that skips `DocumentWriter` reintroduces it — there is a regression test.
- **No hard-coded user-facing strings.** ARB then `flutter gen-l10n`.
- **Layout branches on width class, never `Platform.isX`.**
- **`flutter analyze --fatal-infos` clean; `dart format` produces no changes.** Run the analyzer after every implementation step, not just the tests.
- **Minimum touch target 48x48dp; screen-reader labels on every interactive element.**

### Facts already established by probe — do not re-derive

- An annotation attached by incremental update **renders in PDFium**: a `/Square` changed 5.3% of pixels, page text stayed extractable, 390 bytes overhead.
- **`/Highlight` renders in PDFium without `/AP`** — 1090 pixels changed. But `/AP` is generated anyway (spec §7), because portability to other viewers is the entire reason for writing into the PDF and could not be measured here.
- **`charRects` feed straight into `/QuadPoints`** with no coordinate conversion. Both are PDF user space, y-up.
- **macOS QuickLook is a broken instrument for annotation checks** — it ignores annotations entirely. Do not use `qlmanage` to verify rendering.
- The incremental-update technique assumes a **classic cross-reference table**. PDF 1.5+ xref streams must be refused, not silently mishandled.

### Working agreements from SP-1/SP-2

- `*.g.dart` is gitignored; run `dart run build_runner build --delete-conflicting-outputs` after touching drift schema.
- Fixtures are generated: `dart run scripts/make_fixtures.dart`. Integration tests build their own on-device via `integration_test/fixture_helper.dart`, from the same shared builder — **add new fixtures to both**, they have diverged before.
- Integration tests: iOS simulator `DFC5606D-37F0-4176-A73D-B8214C7F820F`; Android `flutter emulators --launch pixel_api35` then `-d emulator-5554`.
- Integration timing assertions are **pathology bounds, not benchmarks**. Do not tighten them.

---

## File Structure

| Path | Responsibility |
|---|---|
| `lib/data/repositories/document_writer.dart` | The single place a produced document enters the library |
| `lib/domain/annotations/text_markup.dart` | `TextMarkup` value type, `/QuadPoints` conversion |
| `lib/domain/annotations/annotation_session.dart` | Staged markups, undo/redo |
| `lib/domain/annotations/pdf_object_reader.dart` | Minimal page-dictionary parse and re-emit |
| `lib/domain/annotations/pdf_appearance.dart` | `/AP` form XObject content streams |
| `lib/domain/annotations/pdf_annotation_writer.dart` | Incremental update assembling the above |
| `lib/domain/repositories/annotation_repository.dart` | Interface: save a session to a new document |
| `lib/data/repositories/annotation_repository_impl.dart` | Implementation |
| `lib/features/viewer/widgets/markup_toolbar.dart` | Selection → highlight/underline/strike |
| `lib/features/viewer/annotation_providers.dart` | Session state |

---

# Stage 1 — Refactor and pure domain

Runs on any CI runner. No simulator, no native.

---

### Task 1: Extract DocumentWriter

**Files:**
- Create: `lib/data/repositories/document_writer.dart`
- Modify: `lib/data/repositories/page_operations_repository_impl.dart`
- Test: `test/data/repositories/document_writer_test.dart`

**Interfaces:**
- Consumes: `SafeFileWriter`, `LibraryRepository.registerManaged`, `PdfMetadata`
- Produces: `DocumentWriter({required LibraryRepository library, required SafeFileWriter writer, required Directory libraryRoot})` with `Future<LibraryDocument> store(Uint8List bytes, String displayName, {PdfMetadata? metadata})`

Metadata preservation currently lives in a private method of the page-operations repository. Annotations cannot reach it, and a second copy is where the SP-2b bug returns. This extracts it once.

- [ ] **Step 1: Write the failing test**

`test/data/repositories/document_writer_test.dart`:
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
import 'package:folio/domain/editing/pdf_metadata.dart';

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late DocumentWriter subject;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('doc_writer');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
    subject = DocumentWriter(
      library: library,
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Uint8List pdf() => Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 1, 2, 3]);

  test('stores bytes as a new library document', () async {
    final doc = await subject.store(pdf(), 'Out.pdf');

    expect(doc.displayName, 'Out.pdf');
    expect(await library.all(), hasLength(1));
    expect(File(await library.resolveReadablePath(doc)).existsSync(), isTrue);
  });

  test('identical bytes are content-addressed to the same file', () async {
    final a = await subject.store(pdf(), 'A.pdf');
    final b = await subject.store(pdf(), 'B.pdf');

    expect(
      await library.resolveReadablePath(a),
      await library.resolveReadablePath(b),
    );
    expect(await library.all(), hasLength(2), reason: 'two entries, one file');
  });

  // The SP-2b regression guard: any caller that skips metadata loses it.
  test('re-attaches metadata when supplied', () async {
    const meta = PdfMetadata(title: 'Kept', author: 'A Sharma');
    final doc = await subject.store(pdf(), 'Out.pdf', metadata: meta);

    final bytes = await File(
      await library.resolveReadablePath(doc),
    ).readAsBytes();
    final back = PdfMetadata.readFrom(bytes);

    expect(back?.title, 'Kept');
    expect(back?.author, 'A Sharma');
  });

  test('a document that cannot be patched is still stored', () async {
    // No startxref, so appendTo throws; the write must still succeed.
    final junk = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
    const meta = PdfMetadata(title: 'Ignored');

    final doc = await subject.store(junk, 'Out.pdf', metadata: meta);
    expect(await library.all(), hasLength(1));
    expect(File(await library.resolveReadablePath(doc)).existsSync(), isTrue);
  });

  test('empty metadata is a no-op, not an error', () async {
    final doc = await subject.store(pdf(), 'Out.pdf', metadata: const PdfMetadata());
    expect(File(await library.resolveReadablePath(doc)).existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/repositories/document_writer_test.dart`
Expected: FAIL — `Target of URI doesn't exist: document_writer.dart`

- [ ] **Step 3: Implement**

`lib/data/repositories/document_writer.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:path/path.dart' as p;

/// The single place a produced document enters the library.
///
/// Every writer - page operations, annotations, anything later - goes through
/// here, so metadata preservation cannot be forgotten by a new caller. That
/// exact omission was the SP-2b data-loss bug.
class DocumentWriter {
  const DocumentWriter({
    required LibraryRepository library,
    required SafeFileWriter writer,
    required Directory libraryRoot,
  }) : _library = library,
       _writer = writer,
       _root = libraryRoot;

  final LibraryRepository _library;
  final SafeFileWriter _writer;
  final Directory _root;

  /// Writes [bytes] into the library as a new content-addressed document,
  /// re-attaching [metadata] first when supplied.
  ///
  /// Metadata re-attachment is best-effort: a document that cannot be patched
  /// is still written, because losing a title is better than losing the file.
  Future<LibraryDocument> store(
    Uint8List bytes,
    String displayName, {
    PdfMetadata? metadata,
  }) async {
    var payload = bytes;
    if (metadata != null && !metadata.isEmpty) {
      try {
        payload = metadata.appendTo(payload);
      } on FormatException {
        // Not a classic-xref document; keep the unpatched bytes.
      }
    }

    final hash = sha256.convert(payload).toString();
    final relative = p.join(hash.substring(0, 2), '$hash.pdf');

    await _writer.write(
      destination: File(p.join(_root.path, relative)),
      produce: (working) => working.writeAsBytes(payload, flush: true),
      validate: (working) async => await working.length() == payload.length,
    );

    return _library.registerManaged(
      relativePath: relative,
      contentHash: hash,
      displayName: displayName,
      sizeBytes: payload.length,
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/data/repositories/document_writer_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 5: Make page operations use it**

In `lib/data/repositories/page_operations_repository_impl.dart`, delete the private `_store` method and its metadata block, add a `DocumentWriter` field named `_documents`, constructed in the constructor, and replace every `_store(...)` call with `_documents.store(...)`:

```dart
  PageOperationsRepositoryImpl({
    required LibraryRepository library,
    required SafeFileWriter writer,
    required Directory libraryRoot,
    required PdfPageEditor editor,
    required OpenSource openSource,
    required CloseSource closeSource,
  }) : _library = library,
       _documents = DocumentWriter(
         library: library,
         writer: writer,
         libraryRoot: libraryRoot,
       ),
       _editor = editor,
       _open = openSource,
       _close = closeSource;
```

Remove the now-unused `_writer`, `_root`, `sha256` and `path` imports if the analyzer flags them.

- [ ] **Step 6: Verify nothing regressed**

Run: `dart format lib test && flutter analyze --fatal-infos && flutter test`
Expected: analyzer clean; all tests pass, including the existing page-operations metadata tests.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: extract DocumentWriter as the single library write path

Metadata preservation lived in a private method of the page-operations
repository, so a second caller would either duplicate it or silently lose
metadata - reintroducing the SP-2b bug. Now one collaborator every writer
goes through."
```

---

### Task 2: TextMarkup and QuadPoints

**Files:**
- Create: `lib/domain/annotations/text_markup.dart`
- Test: `test/domain/annotations/text_markup_test.dart`

**Interfaces:**
- Consumes: `TextRect` from `lib/domain/engine/pdf_types.dart`
- Produces: `enum MarkupKind { highlight, underline, strikeOut }`; `TextMarkup({required MarkupKind kind, required int pageIndex, required List<TextRect> quads, int colorArgb = 0xFFFFFF00})` with `String get pdfSubtype`, `List<double> get quadPoints`, `String get pdfColour`, `TextRect get boundingRect`

`charRects` are already PDF user space, y-up. `/QuadPoints` ordering per ISO 32000-1 Table 179 is upper-left, upper-right, lower-left, lower-right — **not** clockwise, which is the usual mistake.

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/text_markup_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';

const rect = TextRect(left: 60, top: 712, right: 120, bottom: 700);

void main() {
  group('pdfSubtype', () {
    test('maps each kind to its PDF subtype name', () {
      expect(
        const TextMarkup(
          kind: MarkupKind.highlight,
          pageIndex: 0,
          quads: [rect],
        ).pdfSubtype,
        'Highlight',
      );
      expect(
        const TextMarkup(
          kind: MarkupKind.underline,
          pageIndex: 0,
          quads: [rect],
        ).pdfSubtype,
        'Underline',
      );
      // The PDF name is StrikeOut, not Strikethrough - a wrong name here
      // produces an annotation no viewer recognises.
      expect(
        const TextMarkup(
          kind: MarkupKind.strikeOut,
          pageIndex: 0,
          quads: [rect],
        ).pdfSubtype,
        'StrikeOut',
      );
    });
  });

  group('quadPoints', () {
    // ISO 32000-1 Table 179: upper-left, upper-right, lower-left, lower-right.
    // Clockwise ordering is the common mistake and renders wrong.
    test('emits eight numbers per quad in spec order', () {
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect],
      );
      expect(markup.quadPoints, [60, 712, 120, 712, 60, 700, 120, 700]);
    });

    test('concatenates multiple quads', () {
      const second = TextRect(left: 60, top: 690, right: 200, bottom: 678);
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect, second],
      );
      expect(markup.quadPoints, hasLength(16));
      expect(markup.quadPoints.sublist(8), [60, 690, 200, 690, 60, 678, 200, 678]);
    });

    test('preserves y-up: the first y is the larger value', () {
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect],
      );
      expect(markup.quadPoints[1], greaterThan(markup.quadPoints[5]));
    });
  });

  group('boundingRect', () {
    test('spans every quad', () {
      const a = TextRect(left: 60, top: 712, right: 120, bottom: 700);
      const b = TextRect(left: 40, top: 690, right: 200, bottom: 678);
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [a, b],
      );

      expect(markup.boundingRect.left, 40);
      expect(markup.boundingRect.right, 200);
      expect(markup.boundingRect.top, 712);
      expect(markup.boundingRect.bottom, 678);
    });
  });

  group('pdfColour', () {
    test('converts ARGB to PDF components in 0..1', () {
      const yellow = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect],
      );
      expect(yellow.pdfColour, '1 1 0');
    });

    test('handles a non-primary colour', () {
      const teal = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [rect],
        colorArgb: 0xFF008080,
      );
      final parts = teal.pdfColour.split(' ').map(double.parse).toList();
      expect(parts[0], 0);
      expect(parts[1], closeTo(0.502, 0.01));
      expect(parts[2], closeTo(0.502, 0.01));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/text_markup_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/annotations/text_markup.dart`:
```dart
import 'package:folio/domain/engine/pdf_types.dart';

enum MarkupKind { highlight, underline, strikeOut }

/// One text-markup annotation staged for writing.
///
/// [quads] come straight from `PageText.charRects`, which are already PDF user
/// space with y-up coordinates, so no conversion is needed anywhere.
class TextMarkup {
  const TextMarkup({
    required this.kind,
    required this.pageIndex,
    required this.quads,
    this.colorArgb = 0xFFFFFF00,
  });

  final MarkupKind kind;
  final int pageIndex;
  final List<TextRect> quads;
  final int colorArgb;

  /// The PDF annotation subtype name. Note StrikeOut, not Strikethrough.
  String get pdfSubtype => switch (kind) {
    MarkupKind.highlight => 'Highlight',
    MarkupKind.underline => 'Underline',
    MarkupKind.strikeOut => 'StrikeOut',
  };

  /// Eight numbers per quad, ordered upper-left, upper-right, lower-left,
  /// lower-right per ISO 32000-1 Table 179.
  ///
  /// Clockwise ordering looks natural and is wrong: viewers render it as a
  /// bowtie or not at all.
  List<double> get quadPoints => [
    for (final q in quads) ...[
      q.left, q.top,
      q.right, q.top,
      q.left, q.bottom,
      q.right, q.bottom,
    ],
  ];

  TextRect get boundingRect => TextRect(
    left: quads.map((q) => q.left).reduce((a, b) => a < b ? a : b),
    right: quads.map((q) => q.right).reduce((a, b) => a > b ? a : b),
    top: quads.map((q) => q.top).reduce((a, b) => a > b ? a : b),
    bottom: quads.map((q) => q.bottom).reduce((a, b) => a < b ? a : b),
  );

  /// PDF `/C` components, each 0..1, space separated.
  String get pdfColour {
    String c(int shift) =>
        (((colorArgb >> shift) & 0xFF) / 255).toStringAsFixed(3);
    return '${c(16)} ${c(8)} ${c(0)}'.replaceAll(RegExp(r'\.000\b'), '');
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/text_markup_test.dart`
Expected: PASS — 8 tests

- [ ] **Step 5: Mutation-test the quad ordering**

Change `quadPoints` to clockwise order — swap the third and fourth pairs so it emits `left,top right,top right,bottom left,bottom`. Run the suite.

Expected: `emits eight numbers per quad in spec order` FAILS. Revert and confirm green. This ordering is the single most likely silent defect in the whole slice.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: add TextMarkup with spec-ordered QuadPoints

QuadPoints use ISO 32000-1 Table 179 ordering - upper-left, upper-right,
lower-left, lower-right - not clockwise, which looks natural and renders as
a bowtie. Verified by mutation. Quads come straight from charRects, which
are already PDF user space and y-up."
```

---

### Task 3: AnnotationSession

**Files:**
- Create: `lib/domain/annotations/annotation_session.dart`
- Test: `test/domain/annotations/annotation_session_test.dart`

**Interfaces:**
- Consumes: `TextMarkup` (Task 2)
- Produces: `AnnotationSession()`; `List<TextMarkup> get markups` (unmodifiable); `bool get isEmpty`, `bool get isDirty`, `bool get canUndo`, `bool get canRedo`; `void add(TextMarkup)`, `void removeAt(int)`, `void undo()`, `void redo()`; `List<TextMarkup> markupsOnPage(int pageIndex)`

Deliberately the same shape as `PageEditSession`, so the two read alike.

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/annotation_session_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/annotation_session.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';

TextMarkup markup({MarkupKind kind = MarkupKind.highlight, int page = 0}) =>
    TextMarkup(
      kind: kind,
      pageIndex: page,
      quads: const [TextRect(left: 60, top: 712, right: 120, bottom: 700)],
    );

void main() {
  test('starts empty and clean', () {
    final s = AnnotationSession();
    expect(s.markups, isEmpty);
    expect(s.isEmpty, isTrue);
    expect(s.isDirty, isFalse);
    expect(s.canUndo, isFalse);
  });

  test('markups are unmodifiable from outside', () {
    final s = AnnotationSession();
    expect(() => s.markups.add(markup()), throwsUnsupportedError);
  });

  test('adding makes the session dirty', () {
    final s = AnnotationSession()..add(markup());
    expect(s.markups, hasLength(1));
    expect(s.isDirty, isTrue);
    expect(s.canUndo, isTrue);
  });

  test('removeAt deletes the right one', () {
    final s = AnnotationSession()
      ..add(markup(kind: MarkupKind.highlight))
      ..add(markup(kind: MarkupKind.underline))
      ..removeAt(0);

    expect(s.markups.single.kind, MarkupKind.underline);
  });

  test('an out-of-range removal throws', () {
    final s = AnnotationSession()..add(markup());
    expect(() => s.removeAt(5), throwsRangeError);
  });

  test('undo restores the previous state', () {
    final s = AnnotationSession()..add(markup());
    s.undo();

    expect(s.markups, isEmpty);
    expect(s.isDirty, isFalse);
  });

  test('redo reapplies', () {
    final s = AnnotationSession()..add(markup());
    s.undo();
    s.redo();
    expect(s.markups, hasLength(1));
  });

  test('undo past the beginning is a safe no-op', () {
    final s = AnnotationSession();
    s.undo();
    expect(s.markups, isEmpty);
  });

  test('redo past the end is a safe no-op', () {
    final s = AnnotationSession()..add(markup());
    s.undo();
    s.redo();
    s.redo();
    expect(s.markups, hasLength(1));
  });

  test('a new addition after undo discards the redo branch', () {
    final s = AnnotationSession()..add(markup(kind: MarkupKind.highlight));
    s.undo();
    s.add(markup(kind: MarkupKind.strikeOut));

    expect(s.canRedo, isFalse);
    expect(s.markups.single.kind, MarkupKind.strikeOut);
  });

  test('markupsOnPage filters by page', () {
    final s = AnnotationSession()
      ..add(markup(page: 0))
      ..add(markup(page: 2))
      ..add(markup(page: 0));

    expect(s.markupsOnPage(0), hasLength(2));
    expect(s.markupsOnPage(2), hasLength(1));
    expect(s.markupsOnPage(1), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/annotation_session_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/annotations/annotation_session.dart`:
```dart
import 'package:folio/domain/annotations/text_markup.dart';

/// Markup staged for writing.
///
/// Nothing touches a PDF until the caller saves, so undo is a stack of
/// in-memory snapshots and an abandoned session leaves no files behind. The
/// same shape as PageEditSession, deliberately.
class AnnotationSession {
  List<TextMarkup> _markups = [];
  final List<List<TextMarkup>> _undo = [];
  final List<List<TextMarkup>> _redo = [];

  List<TextMarkup> get markups => List.unmodifiable(_markups);

  bool get isEmpty => _markups.isEmpty;
  bool get isDirty => _markups.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  List<TextMarkup> markupsOnPage(int pageIndex) =>
      _markups.where((m) => m.pageIndex == pageIndex).toList();

  void _mutate(void Function(List<TextMarkup>) change) {
    final snapshot = List.of(_markups);
    final working = List.of(_markups);
    change(working);
    _undo.add(snapshot);
    _redo.clear();
    _markups = working;
  }

  void add(TextMarkup markup) => _mutate((list) => list.add(markup));

  void removeAt(int index) {
    RangeError.checkValidIndex(index, _markups, 'index');
    _mutate((list) => list.removeAt(index));
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(List.of(_markups));
    _markups = _undo.removeLast();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(List.of(_markups));
    _markups = _redo.removeLast();
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/annotation_session_test.dart`
Expected: PASS — 11 tests

- [ ] **Step 5: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: add AnnotationSession with staged markup and undo

Same shape as PageEditSession: snapshots rather than inverse operations, so
undo cannot drift out of sync, and nothing is written until save."
```

---

# Stage 2 — The write path

Ends with: markup written into a real PDF, verified by rendering it back.

---

### Task 4: PdfObjectReader — the bounded parser

**Files:**
- Create: `lib/domain/annotations/pdf_object_reader.dart`
- Test: `test/domain/annotations/pdf_object_reader_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `PdfObjectReader.parse(String pdfText)` returning a reader; `PdfPageObject? pageAt(int index)` with fields `int objectNumber`, `String rawDictionary`, `List<String> existingAnnotRefs`; `String withAnnots(PdfPageObject page, List<String> newRefs)`; `bool get usesXrefStream`

**This file parses page dictionaries and nothing else.** If something needs more, that is a signal to reconsider scope, not to grow this file. The spike's regex broke on nested dictionaries, on pages where `/Type /Page` was not first, and on pages with an existing `/Annots` array.

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/pdf_object_reader_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';

String pdfWith(String pageDict, {String trailerExtra = ''}) =>
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n$pageDict\nendobj\n'
    'xref\n0 4\n0000000000 65535 f \n'
    'trailer\n<< /Size 4 /Root 1 0 R $trailerExtra>>\n'
    'startxref\n9\n%%EOF\n';

void main() {
  group('pageAt', () {
    test('finds a page whose /Type is first', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>'),
      );
      expect(r.pageAt(0)!.objectNumber, 3);
    });

    // The spike's regex failed here: a '>' appears before /Type.
    test('finds a page whose /Type is NOT first, after nested dictionaries', () {
      final r = PdfObjectReader.parse(
        pdfWith(
          '<< /Resources << /Font << /F1 9 0 R >> >> '
          '/MediaBox [0 0 595 842] /Type /Page /Parent 2 0 R >>',
        ),
      );
      expect(r.pageAt(0)!.objectNumber, 3);
    });

    test('returns null for a page index that does not exist', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R >>'),
      );
      expect(r.pageAt(5), isNull);
    });

    test('malformed input yields no pages rather than throwing', () {
      final r = PdfObjectReader.parse('not a pdf');
      expect(r.pageAt(0), isNull);
    });
  });

  group('existingAnnotRefs', () {
    test('is empty when the page has no /Annots', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R >>'),
      );
      expect(r.pageAt(0)!.existingAnnotRefs, isEmpty);
    });

    // Replacing rather than merging would silently delete a user's existing
    // annotations - the worst possible bug in this file.
    test('reads an existing /Annots array', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R /Annots [7 0 R 8 0 R] >>'),
      );
      expect(r.pageAt(0)!.existingAnnotRefs, ['7 0 R', '8 0 R']);
    });

    test('reads a single-entry /Annots array', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Annots [7 0 R] /Parent 2 0 R >>'),
      );
      expect(r.pageAt(0)!.existingAnnotRefs, ['7 0 R']);
    });
  });

  group('withAnnots', () {
    test('adds /Annots to a page that had none', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R >>'),
      );
      final out = r.withAnnots(r.pageAt(0)!, ['9 0 R']);

      expect(out, contains('/Annots [9 0 R]'));
      expect(out, contains('/Type /Page'));
      expect(out.trim().endsWith('>>'), isTrue);
    });

    test('merges with existing refs rather than replacing them', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Annots [7 0 R] /Parent 2 0 R >>'),
      );
      final out = r.withAnnots(r.pageAt(0)!, ['9 0 R']);

      expect(out, contains('7 0 R'));
      expect(out, contains('9 0 R'));
      expect('/Annots'.allMatches(out).length, 1, reason: 'exactly one /Annots');
    });

    test('preserves nested dictionaries untouched', () {
      final r = PdfObjectReader.parse(
        pdfWith(
          '<< /Type /Page /Resources << /Font << /F1 9 0 R >> >> '
          '/Parent 2 0 R >>',
        ),
      );
      final out = r.withAnnots(r.pageAt(0)!, ['9 0 R']);

      expect(out, contains('/Resources << /Font << /F1 9 0 R >> >>'));
    });
  });

  group('usesXrefStream', () {
    test('a classic table is not an xref stream', () {
      final r = PdfObjectReader.parse(
        pdfWith('<< /Type /Page /Parent 2 0 R >>'),
      );
      expect(r.usesXrefStream, isFalse);
    });

    // Refusing loudly beats producing a document whose annotations never show.
    test('detects a cross-reference stream document', () {
      const xrefStreamPdf =
          '%PDF-1.5\n'
          '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
          '4 0 obj\n<< /Type /XRef /Size 5 /W [1 2 1] >>\nstream\n\nendstream\nendobj\n'
          'startxref\n9\n%%EOF\n';
      expect(PdfObjectReader.parse(xrefStreamPdf).usesXrefStream, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_object_reader_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/annotations/pdf_object_reader.dart`:
```dart
/// A page object located in a PDF's text.
class PdfPageObject {
  const PdfPageObject({
    required this.objectNumber,
    required this.rawDictionary,
    required this.existingAnnotRefs,
  });

  final int objectNumber;

  /// The full dictionary including its outer `<<` and `>>`.
  final String rawDictionary;

  /// Indirect references already in `/Annots`, e.g. `7 0 R`.
  final List<String> existingAnnotRefs;
}

/// A deliberately minimal PDF reader: it finds page dictionaries and re-emits
/// them with an added `/Annots`, and does nothing else.
///
/// This is not a general PDF parser and must not become one. If a caller needs
/// more than page dictionaries, that is a signal to reconsider scope rather
/// than to grow this file.
class PdfObjectReader {
  PdfObjectReader._(this._pages, this.usesXrefStream);

  final List<PdfPageObject> _pages;

  /// True when the document uses PDF 1.5+ cross-reference streams, for which
  /// the incremental-update technique does not hold.
  final bool usesXrefStream;

  static PdfObjectReader parse(String pdfText) {
    final pages = <PdfPageObject>[];

    // Every indirect object; the dictionary is matched by brace balance rather
    // than a regex, so nested << >> cannot terminate it early.
    final starts = RegExp(r'(\d+)\s+0\s+obj').allMatches(pdfText);
    for (final start in starts) {
      final open = pdfText.indexOf('<<', start.end);
      if (open < 0) continue;
      final close = _matchingClose(pdfText, open);
      if (close < 0) continue;

      final dict = pdfText.substring(open, close + 2);
      // /Type /Page but not /Pages: the trailing character must not be 's'.
      if (!RegExp(r'/Type\s*/Page(?![a-zA-Z])').hasMatch(dict)) continue;

      pages.add(
        PdfPageObject(
          objectNumber: int.parse(start.group(1)!),
          rawDictionary: dict,
          existingAnnotRefs: _readAnnotRefs(dict),
        ),
      );
    }

    final usesStream = RegExp(r'/Type\s*/XRef').hasMatch(pdfText);
    return PdfObjectReader._(pages, usesStream);
  }

  /// Index of the `>>` closing the `<<` at [openIndex], honouring nesting.
  static int _matchingClose(String text, int openIndex) {
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

  static List<String> _readAnnotRefs(String dict) {
    final match = RegExp(r'/Annots\s*\[([^\]]*)\]').firstMatch(dict);
    if (match == null) return const [];
    return RegExp(r'\d+\s+\d+\s+R')
        .allMatches(match.group(1)!)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ' '))
        .toList();
  }

  PdfPageObject? pageAt(int index) =>
      index >= 0 && index < _pages.length ? _pages[index] : null;

  /// Re-emits [page]'s dictionary with [newRefs] added to `/Annots`.
  ///
  /// Existing references are merged, never replaced: replacing them would
  /// silently delete a user's existing annotations.
  String withAnnots(PdfPageObject page, List<String> newRefs) {
    final all = [...page.existingAnnotRefs, ...newRefs];
    final annots = '/Annots [${all.join(' ')}]';

    final dict = page.rawDictionary;
    if (page.existingAnnotRefs.isEmpty) {
      // Insert before the closing >>.
      final body = dict.substring(2, dict.length - 2).trimRight();
      return '<< $body $annots >>';
    }

    return dict.replaceFirst(RegExp(r'/Annots\s*\[[^\]]*\]'), annots);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_object_reader_test.dart`
Expected: PASS — 12 tests

- [ ] **Step 5: Mutation-test the merge**

In `withAnnots`, change the merge to `final all = [...newRefs];` — dropping existing refs. Run the suite.

Expected: `merges with existing refs rather than replacing them` FAILS. Revert and confirm green. Silently deleting a user's existing annotations is the worst defect this file could ship.

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: add bounded PdfObjectReader for page dictionaries

Matches dictionaries by brace balance rather than regex, so nested << >>
cannot terminate one early - the spike's regex broke on exactly that, and on
pages where /Type /Page is not the first key.

Existing /Annots are merged, never replaced; verified by mutation, because
replacing them would silently delete a user's annotations. Detects PDF 1.5+
cross-reference streams so they can be refused rather than mishandled.

Parses page dictionaries and nothing else, deliberately."
```

---

### Task 5: Appearance streams

**Files:**
- Create: `lib/domain/annotations/pdf_appearance.dart`
- Test: `test/domain/annotations/pdf_appearance_test.dart`

**Interfaces:**
- Consumes: `TextMarkup`, `MarkupKind` (Task 2)
- Produces: `String appearanceStream(TextMarkup markup)` returning the content stream, and `String appearanceDict(TextMarkup markup, int streamLength)` returning the form XObject dictionary

PDFium renders markup without `/AP`, proven by probe. `/AP` is generated anyway because portability to other viewers is the whole reason for writing into the PDF, and could not be measured here (spec §7).

- [ ] **Step 1: Write the failing test**

`test/domain/annotations/pdf_appearance_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';

const quad = TextRect(left: 60, top: 712, right: 120, bottom: 700);

TextMarkup of(MarkupKind kind) =>
    TextMarkup(kind: kind, pageIndex: 0, quads: const [quad]);

void main() {
  group('appearanceStream', () {
    test('highlight fills the quad', () {
      final s = appearanceStream(of(MarkupKind.highlight));
      expect(s, contains('re'), reason: 'a rectangle path');
      expect(s, contains('f'), reason: 'filled');
      expect(s, contains('60'));
    });

    // Without Multiply, a highlight paints over the text and hides it.
    test('highlight uses the Multiply blend mode', () {
      expect(appearanceStream(of(MarkupKind.highlight)), contains('/GSHL gs'));
    });

    test('underline strokes a line at the bottom of the quad', () {
      final s = appearanceStream(of(MarkupKind.underline));
      expect(s, contains('S'), reason: 'stroked, not filled');
      expect(s, contains('700'), reason: 'at the quad bottom');
    });

    test('strikeout strokes a line through the middle of the quad', () {
      final s = appearanceStream(of(MarkupKind.strikeOut));
      expect(s, contains('S'));
      // Midpoint of 700..712 is 706.
      expect(s, contains('706'));
    });

    test('multiple quads each produce their own path', () {
      const second = TextRect(left: 60, top: 690, right: 200, bottom: 678);
      const markup = TextMarkup(
        kind: MarkupKind.highlight,
        pageIndex: 0,
        quads: [quad, second],
      );
      expect('re'.allMatches(appearanceStream(markup)).length, 2);
    });
  });

  group('appearanceDict', () {
    test('is a form XObject with a BBox spanning the markup', () {
      final d = appearanceDict(of(MarkupKind.highlight), 42);

      expect(d, contains('/Type /XObject'));
      expect(d, contains('/Subtype /Form'));
      expect(d, contains('/BBox [60 700 120 712]'));
      expect(d, contains('/Length 42'));
    });

    test('highlight declares the Multiply graphics state', () {
      final d = appearanceDict(of(MarkupKind.highlight), 10);
      expect(d, contains('/ExtGState'));
      expect(d, contains('/Multiply'));
    });

    test('underline needs no graphics state', () {
      final d = appearanceDict(of(MarkupKind.underline), 10);
      expect(d, isNot(contains('/Multiply')));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_appearance_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/annotations/pdf_appearance.dart`:
```dart
import 'package:folio/domain/annotations/text_markup.dart';

/// Content stream for a markup annotation's appearance.
///
/// PDFium renders markup without an appearance stream - proven by probe - but
/// other viewers were not measurable here, and portability is the entire reason
/// annotations are written into the PDF. So one is always generated.
String appearanceStream(TextMarkup markup) {
  final colour = markup.pdfColour;
  final buffer = StringBuffer();

  switch (markup.kind) {
    case MarkupKind.highlight:
      // Multiply keeps the text legible underneath; without it the fill paints
      // over the glyphs and hides them.
      buffer.writeln('/GSHL gs');
      buffer.writeln('$colour rg');
      for (final q in markup.quads) {
        buffer.writeln(
          '${_n(q.left)} ${_n(q.bottom)} '
          '${_n(q.right - q.left)} ${_n(q.top - q.bottom)} re',
        );
      }
      buffer.writeln('f');

    case MarkupKind.underline:
      buffer.writeln('$colour RG');
      buffer.writeln('1 w');
      for (final q in markup.quads) {
        buffer.writeln('${_n(q.left)} ${_n(q.bottom)} m');
        buffer.writeln('${_n(q.right)} ${_n(q.bottom)} l');
      }
      buffer.writeln('S');

    case MarkupKind.strikeOut:
      buffer.writeln('$colour RG');
      buffer.writeln('1 w');
      for (final q in markup.quads) {
        final mid = (q.top + q.bottom) / 2;
        buffer.writeln('${_n(q.left)} ${_n(mid)} m');
        buffer.writeln('${_n(q.right)} ${_n(mid)} l');
      }
      buffer.writeln('S');
  }

  return buffer.toString();
}

/// The form XObject dictionary wrapping [appearanceStream].
String appearanceDict(TextMarkup markup, int streamLength) {
  final b = markup.boundingRect;
  final bbox =
      '[${_n(b.left)} ${_n(b.bottom)} ${_n(b.right)} ${_n(b.top)}]';

  final resources = markup.kind == MarkupKind.highlight
      ? '/Resources << /ExtGState << /GSHL << /Type /ExtGState '
            '/BM /Multiply /ca 1 >> >> >> '
      : '/Resources << >> ';

  return '<< /Type /XObject /Subtype /Form /BBox $bbox '
      '$resources/Length $streamLength >>';
}

/// Trims trailing zeros so the stream stays compact and readable.
String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_appearance_test.dart`
Expected: PASS — 8 tests

- [ ] **Step 5: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos
git add -A
git commit -m "feat: generate appearance streams for text markup

Highlight fills each quad through a Multiply blend so the text stays legible;
underline and strikeout stroke a line at the bottom and midpoint. Generated
even though PDFium does not require it, because portability to other viewers
is why annotations are written into the PDF at all and could not be measured
on this machine."
```

---

### Task 6: PdfAnnotationWriter

**Files:**
- Create: `lib/domain/annotations/pdf_annotation_writer.dart`
- Modify: `lib/core/errors/app_failure.dart`, `lib/core/errors/failure_messages.dart`, `lib/l10n/app_en.arb`
- Test: `test/domain/annotations/pdf_annotation_writer_test.dart`

**Interfaces:**
- Consumes: `PdfObjectReader` (Task 4), `appearanceStream`/`appearanceDict` (Task 5), `TextMarkup` (Task 2)
- Produces: `Uint8List writeMarkup(Uint8List pdf, List<TextMarkup> markups)`; new failure `UnsupportedPdfStructure`

- [ ] **Step 1: Add the failure variant and watch the switch break**

In `lib/core/errors/app_failure.dart`, before `UnknownFailure`:
```dart
final class UnsupportedPdfStructure extends AppFailure {
  const UnsupportedPdfStructure({super.technicalDetail});
  @override
  String get code => 'unsupported_pdf_structure';
}
```

Run: `flutter analyze`
Expected: **error** `non_exhaustive_switch_expression` in `failure_messages.dart` — the guarantee doing its job for the third time.

- [ ] **Step 2: Add the strings and mapping**

Add to `lib/l10n/app_en.arb`:
```json
{
  "errorUnsupportedPdfStructureTitle": "Can't add markup to this PDF.",
  "errorUnsupportedPdfStructureBody": "It uses a newer PDF structure this app can't safely modify yet. The document is unchanged."
}
```

Run `flutter gen-l10n`, then add to the switch in `failure_messages.dart`:
```dart
    UnsupportedPdfStructure() => FailureMessage(
      l10n.errorUnsupportedPdfStructureTitle,
      l10n.errorUnsupportedPdfStructureBody,
    ),
```

Run: `flutter analyze --fatal-infos`
Expected: `No issues found!`

- [ ] **Step 3: Write the failing test**

`test/domain/annotations/pdf_annotation_writer_test.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_annotation_writer.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';

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

TextMarkup markup([MarkupKind kind = MarkupKind.highlight]) => TextMarkup(
  kind: kind,
  pageIndex: 0,
  quads: const [TextRect(left: 60, top: 712, right: 120, bottom: 700)],
);

void main() {
  test('leaves the original bytes untouched at the front', () {
    final original = classicPdf();
    final out = writeMarkup(original, [markup()]);

    expect(out.length, greaterThan(original.length));
    expect(out.sublist(0, original.length), original);
  });

  test('emits the annotation with the right subtype and quads', () {
    final text = latin1.decode(writeMarkup(classicPdf(), [markup()]));

    expect(text, contains('/Subtype /Highlight'));
    expect(text, contains('/QuadPoints'));
    expect(text, contains('60 712 120 712 60 700 120 700'));
  });

  test('emits an appearance stream', () {
    final text = latin1.decode(writeMarkup(classicPdf(), [markup()]));
    expect(text, contains('/Subtype /Form'));
    expect(text, contains('/AP'));
  });

  test('the page object is overridden with /Annots', () {
    final text = latin1.decode(writeMarkup(classicPdf(), [markup()]));
    // The last definition of object 3 must carry /Annots.
    final defs = RegExp(r'3 0 obj(.*?)endobj', dotAll: true).allMatches(text);
    expect(defs.last.group(1), contains('/Annots'));
  });

  test('ends with a trailer chaining to the previous xref', () {
    final text = latin1.decode(writeMarkup(classicPdf(), [markup()]));
    expect(text, contains('/Prev 9'));
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
  });

  test('writes several markups of different kinds', () {
    final text = latin1.decode(
      writeMarkup(classicPdf(), [
        markup(),
        markup(MarkupKind.underline),
        markup(MarkupKind.strikeOut),
      ]),
    );

    expect(text, contains('/Subtype /Highlight'));
    expect(text, contains('/Subtype /Underline'));
    expect(text, contains('/Subtype /StrikeOut'));
  });

  test('an empty markup list returns the document unchanged', () {
    final original = classicPdf();
    expect(writeMarkup(original, const []), original);
  });

  // Refusing loudly beats producing a file whose annotations never appear.
  test('a cross-reference-stream document is refused', () {
    final xrefStream = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.5\n'
        '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        '4 0 obj\n<< /Type /XRef /Size 5 >>\nstream\n\nendstream\nendobj\n'
        'startxref\n9\n%%EOF\n',
      ),
    );

    expect(
      () => writeMarkup(xrefStream, [markup()]),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  test('a document with no page object is refused', () {
    final noPages = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        'trailer\n<< /Size 2 /Root 1 0 R >>\nstartxref\n9\n%%EOF\n',
      ),
    );

    expect(
      () => writeMarkup(noPages, [markup()]),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });
}
```

- [ ] **Step 4: Run to verify it fails**

Run: `flutter test test/domain/annotations/pdf_annotation_writer_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 5: Implement**

`lib/domain/annotations/pdf_annotation_writer.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/annotations/pdf_appearance.dart';
import 'package:folio/domain/annotations/pdf_object_reader.dart';
import 'package:folio/domain/annotations/text_markup.dart';

/// Writes [markups] into [pdf] as real annotation objects, by appending a PDF
/// incremental update.
///
/// The original bytes are never rewritten: new objects, an overridden page
/// dictionary carrying /Annots, a new xref section and a trailer chaining to
/// the previous one are appended. Readers walk that chain backwards.
///
/// Throws [UnsupportedPdfStructure] for documents this technique cannot handle,
/// rather than producing a file whose annotations silently never appear.
Uint8List writeMarkup(Uint8List pdf, List<TextMarkup> markups) {
  if (markups.isEmpty) return pdf;

  final text = latin1.decode(pdf, allowInvalid: true);
  final reader = PdfObjectReader.parse(text);

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

  // objectNumber -> byte offset, for the new xref section.
  final offsets = <int, int>{};

  void emit(int number, String body) {
    offsets[number] = out.length;
    out.addAll(latin1.encode('$number 0 obj\n$body\nendobj\n'));
  }

  // Group by page: each page is overridden once, however many markups it has.
  final byPage = <int, List<TextMarkup>>{};
  for (final m in markups) {
    byPage.putIfAbsent(m.pageIndex, () => []).add(m);
  }

  for (final entry in byPage.entries) {
    final page = reader.pageAt(entry.key);
    if (page == null) {
      throw UnsupportedPdfStructure(
        technicalDetail: 'no page object at index ${entry.key}',
      );
    }

    final newRefs = <String>[];
    for (final markup in entry.value) {
      final stream = appearanceStream(markup);
      final apNum = nextObj++;
      emit(
        apNum,
        '${appearanceDict(markup, stream.length)}\n'
        'stream\n${stream}endstream',
      );

      final annotNum = nextObj++;
      final b = markup.boundingRect;
      emit(
        annotNum,
        '<< /Type /Annot /Subtype /${markup.pdfSubtype} '
        '/Rect [${b.left} ${b.bottom} ${b.right} ${b.top}] '
        '/QuadPoints [${markup.quadPoints.join(' ')}] '
        '/C [${markup.pdfColour}] /CA 1 /F 4 '
        '/AP << /N $apNum 0 R >> >>',
      );
      newRefs.add('$annotNum 0 R');
    }

    emit(page.objectNumber, reader.withAnnots(page, newRefs));
  }

  // One xref subsection per object, which is always valid and avoids having to
  // detect runs of consecutive numbers.
  final xrefOffset = out.length;
  final buffer = StringBuffer('xref\n');
  final numbers = offsets.keys.toList()..sort();
  for (final n in numbers) {
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
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/domain/annotations/pdf_annotation_writer_test.dart`
Expected: PASS — 9 tests

- [ ] **Step 7: Analyze, full suite, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: write text markup as PDF annotations via incremental update

Appends annotation objects, an appearance stream each, an overridden page
dictionary carrying /Annots, a new xref and a trailer chaining to the
previous one. The original bytes are never rewritten.

Refuses cross-reference-stream documents with UnsupportedPdfStructure rather
than producing a file whose annotations silently never appear. The exhaustive
failure switch again refused to compile until the new variant had copy."
```

---

# Stage 3 — Repository, interface, verification

---

### Task 7: AnnotationRepository

**Files:**
- Create: `lib/domain/repositories/annotation_repository.dart`, `lib/data/repositories/annotation_repository_impl.dart`
- Test: `test/data/repositories/annotation_repository_test.dart`

**Interfaces:**
- Consumes: `writeMarkup` (Task 6), `DocumentWriter` (Task 1), `LibraryRepository`, `PdfMetadata`, `editedName`
- Produces: `abstract interface class AnnotationRepository` with `Future<LibraryDocument> saveMarkup({required int sourceDocumentId, required List<TextMarkup> markups})`

- [ ] **Step 1: Write the failing test**

`test/data/repositories/annotation_repository_test.dart`:
```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/annotation_repository_impl.dart';
import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/engine/pdf_types.dart';

void main() {
  late Directory sandbox;
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late AnnotationRepositoryImpl subject;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('annot_repo');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: sandbox,
    );
    subject = AnnotationRepositoryImpl(
      library: library,
      documents: DocumentWriter(
        library: library,
        writer: SafeFileWriter(),
        libraryRoot: sandbox,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// A classic-xref PDF carrying metadata, so both concerns can be asserted.
  Future<int> seed() async {
    final f = File('${sandbox.path}/src.pdf');
    f.writeAsStringSync(
      '%PDF-1.4\n'
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\nendobj\n'
      '4 0 obj\n<< /Title (Kept Title) /Author (A Sharma) >>\nendobj\n'
      'xref\n0 5\n0000000000 65535 f \n'
      'trailer\n<< /Size 5 /Root 1 0 R /Info 4 0 R >>\n'
      'startxref\n9\n%%EOF\n',
    );
    final doc = await library.importFile(f.path, displayName: 'Contract.pdf');
    return doc.id;
  }

  TextMarkup markup() => const TextMarkup(
    kind: MarkupKind.highlight,
    pageIndex: 0,
    quads: [TextRect(left: 60, top: 712, right: 120, bottom: 700)],
  );

  test('creates a new document and leaves the source byte-identical', () async {
    final id = await seed();
    final sourcePath = await library.resolveReadablePath(
      (await library.all()).single,
    );
    final before = await File(sourcePath).readAsBytes();

    final out = await subject.saveMarkup(
      sourceDocumentId: id,
      markups: [markup()],
    );

    expect(out.displayName, 'Contract (edited).pdf');
    expect(await library.all(), hasLength(2));
    expect(await File(sourcePath).readAsBytes(), before);
  });

  test('the output carries the annotation', () async {
    final id = await seed();
    final out = await subject.saveMarkup(
      sourceDocumentId: id,
      markups: [markup()],
    );

    final text = await File(
      await library.resolveReadablePath(out),
    ).readAsString();
    expect(text, contains('/Subtype /Highlight'));
  });

  // The SP-2b regression guard, on the new write path.
  test('metadata survives the annotation save', () async {
    final id = await seed();
    final out = await subject.saveMarkup(
      sourceDocumentId: id,
      markups: [markup()],
    );

    final meta = PdfMetadata.readFrom(
      await File(await library.resolveReadablePath(out)).readAsBytes(),
    );
    expect(meta?.title, 'Kept Title');
    expect(meta?.author, 'A Sharma');
  });

  test('an empty markup list is rejected before anything is written', () async {
    final id = await seed();

    await expectLater(
      subject.saveMarkup(sourceDocumentId: id, markups: const []),
      throwsA(isA<ArgumentError>()),
    );
    expect(await library.all(), hasLength(1));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/repositories/annotation_repository_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement the interface**

`lib/domain/repositories/annotation_repository.dart`:
```dart
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/models/library_document.dart';

/// Saves staged markup into a new document.
///
/// Like page operations, this never modifies its source.
abstract interface class AnnotationRepository {
  Future<LibraryDocument> saveMarkup({
    required int sourceDocumentId,
    required List<TextMarkup> markups,
  });
}
```

- [ ] **Step 4: Implement**

`lib/data/repositories/annotation_repository_impl.dart`:
```dart
import 'dart:io';

import 'package:folio/data/repositories/document_writer.dart';
import 'package:folio/domain/annotations/pdf_annotation_writer.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/editing/pdf_metadata.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/annotation_repository.dart';
import 'package:folio/domain/repositories/library_repository.dart';
import 'package:folio/domain/services/edited_name.dart';

class AnnotationRepositoryImpl implements AnnotationRepository {
  const AnnotationRepositoryImpl({
    required LibraryRepository library,
    required DocumentWriter documents,
  }) : _library = library,
       _documents = documents;

  final LibraryRepository _library;
  final DocumentWriter _documents;

  @override
  Future<LibraryDocument> saveMarkup({
    required int sourceDocumentId,
    required List<TextMarkup> markups,
  }) async {
    if (markups.isEmpty) {
      throw ArgumentError.value(
        markups,
        'markups',
        'nothing to save',
      );
    }

    final source = (await _library.all()).firstWhere(
      (d) => d.id == sourceDocumentId,
    );
    final bytes = await File(
      await _library.resolveReadablePath(source),
    ).readAsBytes();

    // Read metadata from the source: writeMarkup appends to the document, and
    // going through DocumentWriter re-attaches it on the way out.
    final metadata = PdfMetadata.readFrom(bytes);
    final annotated = writeMarkup(bytes, markups);

    return _documents.store(
      annotated,
      editedName(source.displayName),
      metadata: metadata,
    );
  }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/data/repositories/annotation_repository_test.dart`
Expected: PASS — 4 tests

- [ ] **Step 6: Analyze and commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add AnnotationRepository

Saves markup into a new document through DocumentWriter, so metadata
preservation is inherited rather than reimplemented. The source stays
byte-identical, asserted by test."
```

---

### Task 8: Markup toolbar in the viewer

**Files:**
- Create: `lib/features/viewer/annotation_providers.dart`, `lib/features/viewer/widgets/markup_toolbar.dart`
- Modify: `lib/features/viewer/viewer_screen.dart`, `lib/l10n/app_en.arb`, `lib/main.dart`
- Test: `test/features/viewer/annotation_controller_test.dart`

**Interfaces:**
- Consumes: `AnnotationSession` (Task 3), `AnnotationRepository` (Task 7), `PdfEngine.extractText`
- Produces: `annotationRepositoryProvider`, `annotationSessionProvider` (a `NotifierProvider<AnnotationController, AnnotationState>`), `MarkupToolbar`

- [ ] **Step 1: Add the strings**

Add to `lib/l10n/app_en.arb`:
```json
{
  "markupHighlight": "Highlight",
  "markupUnderline": "Underline",
  "markupStrikeOut": "Strikethrough",
  "markupUndo": "Undo markup",
  "markupSave": "Save with markup",
  "markupCount": "{count} marked",
  "@markupCount": { "placeholders": { "count": { "type": "int" } } },
  "markupSaved": "Saved as {name}",
  "@markupSaved": { "placeholders": { "name": { "type": "String" } } },
  "markupSelectFirst": "Select some text to mark it up."
}
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing controller test**

`test/features/viewer/annotation_controller_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/features/viewer/annotation_providers.dart';

const quad = TextRect(left: 60, top: 712, right: 120, bottom: 700);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  AnnotationController controller() =>
      container.read(annotationSessionProvider.notifier);
  AnnotationState state() => container.read(annotationSessionProvider);

  test('starts empty', () {
    expect(state().session.markups, isEmpty);
    expect(state().session.isDirty, isFalse);
  });

  test('adding markup from a selection stages it', () {
    controller().addMarkup(
      kind: MarkupKind.highlight,
      pageIndex: 0,
      quads: const [quad],
    );

    expect(state().session.markups, hasLength(1));
    expect(state().session.markups.single.kind, MarkupKind.highlight);
  });

  test('an empty selection adds nothing', () {
    controller().addMarkup(
      kind: MarkupKind.highlight,
      pageIndex: 0,
      quads: const [],
    );
    expect(state().session.markups, isEmpty);
  });

  test('undo removes the last markup', () {
    controller()
      ..addMarkup(kind: MarkupKind.highlight, pageIndex: 0, quads: const [quad])
      ..undo();

    expect(state().session.markups, isEmpty);
  });

  test('reset clears the session', () {
    controller()
      ..addMarkup(kind: MarkupKind.underline, pageIndex: 0, quads: const [quad])
      ..reset();

    expect(state().session.markups, isEmpty);
    expect(state().session.canUndo, isFalse);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/viewer/annotation_controller_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 4: Implement the providers**

`lib/features/viewer/annotation_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/annotations/annotation_session.dart';
import 'package:folio/domain/annotations/text_markup.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/repositories/annotation_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final annotationRepositoryProvider = Provider<AnnotationRepository>(
  (ref) => throw UnimplementedError(
    'annotationRepositoryProvider must be overridden',
  ),
);

class AnnotationState {
  const AnnotationState({required this.session, required this.busy});

  final AnnotationSession session;
  final bool busy;

  AnnotationState copyWith({bool? busy}) =>
      AnnotationState(session: session, busy: busy ?? this.busy);
}

final annotationSessionProvider =
    NotifierProvider<AnnotationController, AnnotationState>(
      AnnotationController.new,
    );

class AnnotationController extends Notifier<AnnotationState> {
  @override
  AnnotationState build() =>
      AnnotationState(session: AnnotationSession(), busy: false);

  /// The session mutates in place, so emit a new state object to notify
  /// listeners - the same pattern PageSessionController uses.
  void _touch() => state = state.copyWith();

  void addMarkup({
    required MarkupKind kind,
    required int pageIndex,
    required List<TextRect> quads,
  }) {
    if (quads.isEmpty) return;
    state.session.add(
      TextMarkup(kind: kind, pageIndex: pageIndex, quads: quads),
    );
    _touch();
  }

  void undo() {
    state.session.undo();
    _touch();
  }

  void reset() {
    state = AnnotationState(session: AnnotationSession(), busy: false);
  }

  void setBusy(bool value) => state = state.copyWith(busy: value);
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/viewer/annotation_controller_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 6: Build the toolbar**

`lib/features/viewer/widgets/markup_toolbar.dart` shows three buttons — highlight, underline, strikethrough — plus undo and a filled **Save with markup** enabled only when `session.isDirty`. Each markup button is disabled when there is no active text selection. Follow `PageToolbar`'s layout exactly, and **keep Save in the always-visible row, never inside a horizontally scrolling one** — that was a real defect in SP-2a.

- [ ] **Step 7: Wire selection to markup**

In `viewer_screen.dart`, `PdfViewerParams.textSelectionParams` already enables selection. Obtain the selected ranges through the text-selection delegate, convert them to `TextRect` quads via `PdfEngine.extractText(...).charRects`, and pass them to `controller.addMarkup`. Pending markup is painted through the existing `pagePaintCallbacks` list, alongside the search highlighter, so unsaved marks are visible before saving.

Add a markup-mode toggle to the app bar beside the Pages toggle, following the same `_ViewerMode` pattern.

- [ ] **Step 8: Wire the repository in main.dart**

```dart
  final documents = DocumentWriter(
    library: library,
    writer: SafeFileWriter(),
    libraryRoot: libraryRoot,
  );
  final annotations = AnnotationRepositoryImpl(
    library: library,
    documents: documents,
  );
```
and add `annotationRepositoryProvider.overrideWithValue(annotations)` to the `ProviderScope` overrides.

- [ ] **Step 9: Verify on the simulator**

```bash
flutter run -d DFC5606D-37F0-4176-A73D-B8214C7F820F --dart-define-from-file=config/development.json
```

Open *Confidential Invoice.pdf*, select text, highlight it, undo, highlight again, then Save with markup. Confirm a new document appears and the original opens unmarked. **Demo this on the simulator.**

- [ ] **Step 10: Analyze, test, commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: add markup toolbar and selection-driven annotation

Selection quads come from charRects, so no coordinate conversion is needed.
Pending markup paints through the existing pagePaintCallbacks list beside the
search highlighter. Save stays in the always-visible row, not the scrolling
one - that was a real defect in SP-2a."
```

---

### Task 9: End-to-end verification and documentation

**Files:**
- Create: `integration_test/markup_flow_test.dart`
- Modify: `docs/FEATURES.md`, `docs/LIMITATIONS.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`

- [ ] **Step 1: Write the end-to-end test**

`integration_test/markup_flow_test.dart` builds a real library, saves markup through `AnnotationRepositoryImpl`, then reopens the output and asserts:

1. the document opens and its page count is unchanged
2. **the annotation renders** — render the page before and after and require the pixels to differ, the same check both spikes used, because a file that merely opens proves nothing
3. extracted text is unchanged, so markup did not disturb content
4. the source document's SHA-256 is unchanged
5. metadata still survives, so SP-2b has not regressed
6. a page that already had annotations keeps them and gains the new one
7. a cross-reference-stream document is refused with `UnsupportedPdfStructure`

Fixtures needed: reuse `with_metadata.pdf`; add `xref_stream.pdf` to **both** `scripts/pdf_fixture_builder.dart` and `integration_test/fixture_helper.dart` — they have diverged before.

- [ ] **Step 2: Run on the iOS simulator**

```bash
dart run scripts/make_fixtures.dart
flutter test integration_test -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including SP-1 and SP-2 suites.

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

- `FEATURES.md` — add highlight, underline and strikethrough, ✅ where verified, 🟡 for Windows.
- `ARCHITECTURE.md` — document `DocumentWriter` as the single library write path, and the annotation incremental-update approach with its classic-xref limitation.
- `LIMITATIONS.md` — record that markup cannot be added to cross-reference-stream documents, and that saved markup cannot yet be edited or deleted (SP-3b).
- `TESTING.md` — refresh counts and the date.

- [ ] **Step 6: Full verification and push**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
git add -A && git commit -m "test: add end-to-end markup flows and update docs

Every flow reopens the output and requires the annotation to RENDER, not
merely that the file opens. Source documents asserted byte-identical by hash,
and metadata asserted to survive so SP-2b has not regressed."
git push origin feature/sp3a-text-markup
```

Confirm all four CI jobs pass, including `build-windows`.

---

## Definition of done

- [ ] Highlight, underline and strikethrough create, undo and save
- [ ] Saved annotations **render** on reopen, verified by pixel comparison
- [ ] Source documents byte-identical after every save, by SHA-256
- [ ] Metadata survives the annotation path
- [ ] Cross-reference-stream documents refused with a clear message
- [ ] `PdfEngine` still has no write method
- [ ] `lib/domain/annotations` unit coverage ≥90%
- [ ] Integration passes on iOS simulator **and** Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] CI green on all four jobs
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

**Next:** SP-3b — freehand ink and shapes, which needs a drawing surface but inherits this write path — and editing or deleting saved annotations, which needs reading `/Annots` back.
