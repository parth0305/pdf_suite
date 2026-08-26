# SP-5a — Object Layer and Encryption Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite a whole PDF from parsed objects, and encrypt every string and stream on the way out.

**Architecture:** Every write Folio does today appends an incremental update. Encryption cannot: encrypting a document means encrypting every string and stream, so every object must be re-emitted. This builds the full-file writer that makes that possible and proves the pipeline with RC4 — whose algorithms already exist, tested, in `scripts/pdf_encrypt.dart`. No user-facing feature ships.

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5, pdfrx 2.4.7 (PDFium), `package:crypto` (MD5, already a dependency).

**Spec:** `docs/superpowers/specs/2026-08-27-sp5a-object-layer-design.md`

## Global Constraints

- **Zero AI, zero paid or proprietary SDKs, no GPL/LGPL/AGPL.** No new dependencies — RC4 is hand-written and MD5 comes from `package:crypto`, which we already have.
- **Never destroy originals.** Nothing in this slice writes over a source document.
- **`PdfEngine` has no write method and must not gain one.**
- **`PdfObjectReader` handles page dictionaries and nothing else.** The object layer is new files, not growth of that one.
- **Never log document content, passwords, filenames or paths.** A password is the most sensitive thing this codebase will ever hold: it must never reach a log, an error message, or an exception's `toString`.
- **No user-facing encryption action ships in this slice.** RC4-40 is not protection worth offering; the button arrives in SP-5b with AES-256.
- **A feature is not done until it has been verified by rendering.**
- Run `dart format lib test integration_test scripts` and `flutter analyze --fatal-infos` before every commit.

## Critical context the implementer will not guess

**The round-trip is already proven.** A throwaway 77-line model parsed every object out of `sample_3page.pdf`, rebuilt the file with a fresh xref and trailer, and PDFium rendered it with **zero pixels different**. This task is that spike done properly.

**`/Length` is why parsing is not a regex.** Binary stream data can contain the bytes `endobj`. Skipping a stream by its declared `/Length` is the only safe way to find where an object really ends.

**Three files import `scripts/pdf_encrypt.dart`, and one runs on device.** `integration_test/fixture_helper.dart` builds encrypted fixtures **at runtime on the phone and simulator** rather than shipping megabytes of them. The move is therefore verified by the integration suite, not just unit tests.

**`buildEncryptedPdf` injects its algorithms as function parameters**, so `scripts/pdf_fixture_builder.dart` needs no change at all. Only import sites move.

**The existing handler is R2 (RC4-40), not R4.** A five-byte key, `/U` by Algorithm 4. Do not "upgrade" it in this slice — R2 is what is proven, and the cipher is not what is under test here.

**`/Encrypt` and `/ID` are never encrypted.** A reader needs both before it can derive a key. Encrypting either produces a document nothing can open.

## File structure

| File | Responsibility |
|---|---|
| `lib/domain/pdf/pdf_object.dart` | **New.** `PdfObject` and `parsePdfObjects`. |
| `lib/domain/pdf/pdf_document_writer.dart` | **New.** Full rewrite: header, objects, fresh xref, trailer. |
| `lib/domain/pdf/pdf_encryption.dart` | **New.** `scripts/pdf_encrypt.dart` moved here verbatim, plus `encryptObjectBody`. |
| `lib/domain/pdf/pdf_encryption_dictionary.dart` | **New.** The R2 `/Encrypt` dictionary. |
| `scripts/pdf_encrypt.dart` | **Delete.** Its importers point at `lib/` instead. |
| `scripts/make_fixtures.dart` | **Modify.** Import from `package:folio/…`. |
| `integration_test/fixture_helper.dart` | **Modify.** Same. |
| `test/scripts/pdf_encrypt_test.dart` | **Move** to `test/domain/pdf/pdf_encryption_test.dart`, unchanged. |

---

# Stage 1 — Reading and rewriting

Ends with: a document taken apart and put back together, rendering identically.

---

### Task 1: Parsing every object

**Files:**
- Create: `lib/domain/pdf/pdf_object.dart`
- Test: `test/domain/pdf/pdf_object_test.dart`

**Interfaces:**
- Produces: `PdfObject({required int number, required int generation, required List<int> body})`; `List<PdfObject> parsePdfObjects(List<int> bytes)`

- [ ] **Step 1: Write the failing test**

`test/domain/pdf/pdf_object_test.dart`:
```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

List<int> bytesOf(String s) => latin1.encode(s);

void main() {
  test('finds every object with its number and generation', () {
    final objects = parsePdfObjects(
      bytesOf(
        '%PDF-1.4\n'
        '1 0 obj\n<< /Type /Catalog >>\nendobj\n'
        '7 2 obj\n<< /Type /Annot >>\nendobj\n',
      ),
    );

    expect(objects.map((o) => o.number), [1, 7]);
    expect(objects.map((o) => o.generation), [0, 2]);
  });

  test('captures the body between obj and endobj', () {
    final objects = parsePdfObjects(
      bytesOf('1 0 obj\n<< /Type /Catalog >>\nendobj\n'),
    );

    expect(latin1.decode(objects.single.body), contains('/Type /Catalog'));
    expect(latin1.decode(objects.single.body), isNot(contains('endobj')));
  });

  // Binary stream data can contain the bytes `endobj`. Searching for that word
  // ends the object in the middle of its own stream and corrupts everything
  // after it.
  test('a stream containing the bytes endobj does not end the object', () {
    const payload = 'AAendobjBB';
    final objects = parsePdfObjects(
      bytesOf(
        '4 0 obj\n<< /Length ${payload.length} >>\nstream\n'
        '${payload}\nendstream\nendobj\n'
        '5 0 obj\n<< /Type /Page >>\nendobj\n',
      ),
    );

    expect(objects.map((o) => o.number), [4, 5]);
    expect(latin1.decode(objects.first.body), contains(payload));
  });

  test('handles a stream whose data begins after CRLF', () {
    const payload = 'hello';
    final objects = parsePdfObjects(
      bytesOf(
        '4 0 obj\n<< /Length ${payload.length} >>\nstream\r\n'
        '${payload}\r\nendstream\nendobj\n',
      ),
    );

    expect(objects, hasLength(1));
    expect(latin1.decode(objects.single.body), contains(payload));
  });

  test('an object with no stream is unaffected', () {
    final objects = parsePdfObjects(
      bytesOf('3 0 obj\n<< /Type /Page /MediaBox [0 0 595 842] >>\nendobj\n'),
    );

    expect(latin1.decode(objects.single.body), contains('/MediaBox'));
  });

  test('a truncated object is skipped rather than throwing', () {
    final objects = parsePdfObjects(bytesOf('9 0 obj\n<< /Type /Page >>\n'));
    expect(objects, isEmpty);
  });

  test('reads every object out of the real fixture', () {
    // Nine objects, per the spike.
    final objects = parsePdfObjects(bytesOf('1 0 obj\n<< >>\nendobj\n' * 9));
    expect(objects, hasLength(9));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/pdf/pdf_object_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/pdf/pdf_object.dart`:
```dart
import 'dart:convert';

/// One indirect object, captured as raw bytes.
class PdfObject {
  const PdfObject({
    required this.number,
    required this.generation,
    required this.body,
  });

  final int number;
  final int generation;

  /// Everything between `obj` and `endobj`, streams included.
  final List<int> body;
}

/// Every indirect object in [bytes], in file order.
///
/// A stream's declared `/Length` is honoured when looking for the end of an
/// object: binary stream data can contain the bytes `endobj`, and searching
/// for that word would end the object inside its own stream.
List<PdfObject> parsePdfObjects(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final objects = <PdfObject>[];

  for (final match in RegExp(r'(\d+)\s+(\d+)\s+obj').allMatches(text)) {
    final start = match.end;

    final endAt = text.indexOf('endobj', start);
    final streamAt = text.indexOf('stream', start);
    var searchFrom = start;

    // Only treat it as a stream if `stream` comes before this object's end.
    if (streamAt >= 0 && (endAt < 0 || streamAt < endAt)) {
      final length = RegExp(
        r'/Length\s+(\d+)',
      ).firstMatch(text.substring(start, streamAt));
      if (length != null) {
        var dataStart = streamAt + 'stream'.length;
        // The keyword is followed by CRLF or LF, never CR alone.
        if (text.startsWith('\r\n', dataStart)) {
          dataStart += 2;
        } else if (text.startsWith('\n', dataStart)) {
          dataStart += 1;
        }
        searchFrom = dataStart + int.parse(length.group(1)!);
      }
    }

    final end = text.indexOf('endobj', searchFrom);
    // A truncated object is a damaged document, not a reason to throw.
    if (end < 0) continue;

    objects.add(
      PdfObject(
        number: int.parse(match.group(1)!),
        generation: int.parse(match.group(2)!),
        body: bytes.sublist(start, end),
      ),
    );
  }

  return objects;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/pdf/pdf_object_test.dart`
Expected: PASS — 7 tests

- [ ] **Step 5: Mutation-test the /Length skip**

Delete the whole `if (streamAt >= 0 …)` block so the parser searches for `endobj` from the start of the object. Run the test file.

Expected: `a stream containing the bytes endobj does not end the object` FAILS — the first object's body is cut short and object 5 is still found, so the count is right but the body is wrong. Revert.

- [ ] **Step 6: Commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: parse every indirect object out of a PDF

A stream's declared /Length is honoured when looking for the end of an object.
Binary stream data can contain the bytes endobj, and searching for that word
ends the object inside its own stream and corrupts everything after it."
```

---

### Task 2: Rewriting the whole document

**Files:**
- Create: `lib/domain/pdf/pdf_document_writer.dart`
- Test: `test/domain/pdf/pdf_document_writer_test.dart`, `integration_test/object_layer_flow_test.dart`

**Interfaces:**
- Consumes: `PdfObject`, `parsePdfObjects` (Task 1)
- Produces: `Uint8List writePdfDocument(List<int> original, List<PdfObject> objects)`. **Task 5 widens this** to `{PdfEncryption? encryption}`; do not add the parameter here, so this task's tests exercise the rewrite on its own.

- [ ] **Step 1: Write the failing unit test**

`test/domain/pdf/pdf_document_writer_test.dart`:
```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

const source =
    '%PDF-1.4\n'
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>\n'
    'endobj\n'
    'xref\n0 4\n0000000000 65535 f \n'
    'trailer\n<< /Size 4 /Root 1 0 R /Info 9 0 R >>\n'
    'startxref\n9\n%%EOF\n';

List<int> bytesOf(String s) => latin1.encode(s);

String rewritten() => latin1.decode(
  writePdfDocument(bytesOf(source), parsePdfObjects(bytesOf(source))),
);

void main() {
  test('emits every object it was given', () {
    final out = rewritten();

    for (final n in [1, 2, 3]) {
      expect(out, contains('$n 0 obj'), reason: 'object $n');
    }
  });

  test('carries /Root and /Info into the new trailer', () {
    final out = rewritten();

    expect(out, contains('/Root 1 0 R'));
    expect(out, contains('/Info 9 0 R'));
  });

  // This is a rewrite, not an incremental update. A /Prev would point at a
  // cross-reference table that no longer exists in the new file.
  test('the trailer has no /Prev', () {
    expect(rewritten(), isNot(contains('/Prev')));
  });

  test('starts with a PDF header and ends with EOF', () {
    final out = rewritten();

    expect(out.startsWith('%PDF-'), isTrue);
    expect(out.trimRight().endsWith('%%EOF'), isTrue);
  });

  test('the xref offsets point at the objects', () {
    final out = rewritten();
    final xrefAt = out.lastIndexOf('xref');
    final entries = RegExp(
      r'^(\d{10}) 00000 n $',
      multiLine: true,
    ).allMatches(out.substring(xrefAt)).toList();

    expect(entries, hasLength(3));
    for (final e in entries) {
      final offset = int.parse(e.group(1)!);
      // An offset that does not land on `N G obj` is a broken xref, and a
      // reader will refuse the file or silently lose the object.
      expect(
        RegExp(r'^\d+ \d+ obj').hasMatch(out.substring(offset)),
        isTrue,
        reason: 'offset $offset should point at an object header',
      );
    }
  });

  test('a document with no objects is refused', () {
    expect(
      () => writePdfDocument(bytesOf('%PDF-1.4\n'), const []),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });

  test('a document with no /Root is refused', () {
    const noRoot = '1 0 obj\n<< >>\nendobj\ntrailer\n<< /Size 2 >>\n%%EOF\n';
    expect(
      () => writePdfDocument(bytesOf(noRoot), parsePdfObjects(bytesOf(noRoot))),
      throwsA(isA<UnsupportedPdfStructure>()),
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/pdf/pdf_document_writer_test.dart`
Expected: FAIL — URI does not exist

- [ ] **Step 3: Implement**

`lib/domain/pdf/pdf_document_writer.dart`:
```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/pdf/pdf_object.dart';

/// Rebuilds a complete PDF: header, every object, a fresh cross-reference
/// table, a trailer.
///
/// This is a REWRITE, not an incremental update - there is no `/Prev`, because
/// the previous cross-reference table does not exist in the new file. That is
/// what encryption needs: every string and stream has to be re-emitted, and
/// nothing can be appended to achieve it.
Uint8List writePdfDocument(List<int> original, List<PdfObject> objects) {
  if (objects.isEmpty) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'no indirect objects found',
    );
  }

  final text = latin1.decode(original, allowInvalid: true);
  final roots = RegExp(r'/Root\s+(\d+)\s+(\d+)\s+R').allMatches(text);
  if (roots.isEmpty) {
    throw const UnsupportedPdfStructure(
      technicalDetail: 'no /Root in any trailer',
    );
  }
  final root = roots.last;
  final infos = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R').allMatches(text);

  // The binary comment marks the file as containing 8-bit data, so tools do
  // not mangle it as text.
  final out = <int>[...latin1.encode('%PDF-1.4\n%âãÏÓ\n')];
  final offsets = <int, int>{};

  for (final o in objects) {
    offsets[o.number] = out.length;
    out
      ..addAll(latin1.encode('${o.number} ${o.generation} obj'))
      ..addAll(o.body)
      ..addAll(latin1.encode('endobj\n'));
  }

  final highest = objects.map((o) => o.number).reduce((a, b) => a > b ? a : b);
  final xrefOffset = out.length;

  final buffer = StringBuffer('xref\n0 ${highest + 1}\n')
    ..writeln('0000000000 65535 f ');
  for (var n = 1; n <= highest; n++) {
    final at = offsets[n];
    // A number nobody used is a free entry, not an error.
    buffer.writeln(
      at == null
          ? '0000000000 65535 f '
          : '${at.toString().padLeft(10, '0')} 00000 n ',
    );
  }

  buffer
    ..writeln('trailer')
    ..writeln(
      '<< /Size ${highest + 1} /Root ${root.group(1)} ${root.group(2)} R'
      '${infos.isEmpty ? '' : ' /Info ${infos.last.group(1)} '
          '${infos.last.group(2)} R'} >>',
    )
    ..writeln('startxref')
    ..writeln('$xrefOffset')
    ..write('%%EOF\n');
  out.addAll(latin1.encode(buffer.toString()));

  return Uint8List.fromList(out);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/pdf/pdf_document_writer_test.dart`
Expected: PASS — 7 tests

- [ ] **Step 5: Write the end-to-end round-trip**

`integration_test/object_layer_flow_test.dart` carries `@Timeout(Duration(minutes: 5))`, opens the real fixture, rewrites it, and asserts by **rendering**:

```dart
    test('a rewritten document renders identically', () async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();

      final rebuilt = writePdfDocument(original, parsePdfObjects(original));

      final before = await renderBytes(original, 'before');
      final after = await renderBytes(rebuilt, 'after');

      var changed = 0;
      for (var i = 0; i < before.length; i++) {
        if (before[i] != after[i]) changed++;
      }
      expect(
        changed,
        0,
        reason: 'a rewrite must not change a single pixel',
      );
    });
```

with `renderBytes` writing the bytes to a temp file, opening through
`PdfrxEngine`, rendering page 0 at 400×566, and closing. Add a second test
asserting the rewritten document still reports three pages, and a third
asserting its text still extracts — a corrupted rewrite can still render a
blank page.

Register it in `integration_test/all_tests.dart`:
```dart
import 'object_layer_flow_test.dart' as object_layer_flow;
// ...
  group('object_layer_flow', object_layer_flow.main);
```

- [ ] **Step 6: Run it on the simulator**

```bash
flutter test integration_test/object_layer_flow_test.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: PASS, with **0** pixels changed.

- [ ] **Step 7: Prove the pixel assertion bites**

In the writer, skip the last object: `for (final o in objects.take(objects.length - 1))`. Re-run the flow file.

Expected: `a rewritten document renders identically` FAILS. Revert. If it passes, the assertion is measuring nothing and must be strengthened before this slice ships.

- [ ] **Step 8: Commit**

```bash
dart format lib test integration_test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: rewrite a whole PDF from its parsed objects

Header, every object, a fresh cross-reference table, a trailer, and no /Prev:
this is a rewrite, not an incremental update. Encryption needs it, because
every string and stream must be re-emitted and nothing can be appended to
achieve that.

Verified by rendering: a rewritten document differs by zero pixels."
```

---

# Stage 2 — Moving the crypto into the app

Ends with: the encryption algorithms shipping in `lib/`, still proven by the same vectors.

---

### Task 3: Move the encryption module

**Files:**
- Create: `lib/domain/pdf/pdf_encryption.dart`
- Delete: `scripts/pdf_encrypt.dart`
- Move: `test/scripts/pdf_encrypt_test.dart` → `test/domain/pdf/pdf_encryption_test.dart`
- Modify: `scripts/make_fixtures.dart`, `integration_test/fixture_helper.dart`

**Interfaces:**
- Produces: from `package:folio/domain/pdf/pdf_encryption.dart` — `kPadding`, `rc4`, `padPassword`, `computeOwnerValue`, `computeEncryptionKey`, `computeUserValue`, `objectKey`, `hexString`, all with their existing signatures unchanged

- [ ] **Step 1: Move the file verbatim**

```bash
git mv scripts/pdf_encrypt.dart lib/domain/pdf/pdf_encryption.dart
git mv test/scripts/pdf_encrypt_test.dart test/domain/pdf/pdf_encryption_test.dart
```

Change only the header comment, which currently says the app does not author
encryption:

```dart
// PDF standard security handler, revision 2 (RC4, 40-bit), per ISO 32000-1
// section 7.6.3.
//
// Written by hand because no permissively licensed Dart package produces an
// encrypted PDF. It began life generating test fixtures; SP-5a moved it into
// the app, where the object layer uses it to encrypt documents.
//
// RC4-40 is NOT protection worth offering to a user. Nothing in the app
// exposes it: it exists to prove the encryption pipeline against a cipher that
// is already verified, so that when AES-256 arrives the only new variable is
// the cipher.
```

- [ ] **Step 2: Point the three importers at the new location**

In `test/domain/pdf/pdf_encryption_test.dart`:
```dart
import 'package:folio/domain/pdf/pdf_encryption.dart';
```

In `scripts/make_fixtures.dart` and `integration_test/fixture_helper.dart`,
replace the relative import with the same package import.

- [ ] **Step 3: Run to verify nothing changed**

Run: `dart format lib test integration_test scripts && flutter analyze --fatal-infos && flutter test`
Expected: all pass, including the moved vectors. The move is behaviour-preserving and those tests are what say so.

- [ ] **Step 4: Verify the on-device fixture path still works**

```bash
flutter test integration_test/all_tests.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass. `integration_test/fixture_helper.dart` builds encrypted fixtures **at runtime on the device**, so this is the check that the move did not break the phone, not just the host.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: move the PDF encryption module into the app

It was written to generate fixtures and lived in scripts/, but the object layer
needs it and integration tests were already importing it across that boundary
to build encrypted fixtures on the device.

Behaviour is unchanged; the vectors that prove it moved with it."
```

---

### Task 4: Encrypting an object's strings and streams

**Files:**
- Modify: `lib/domain/pdf/pdf_encryption.dart`
- Create: `lib/domain/pdf/pdf_encryption_dictionary.dart`
- Test: `test/domain/pdf/pdf_encryption_test.dart`

**Interfaces:**
- Consumes: `rc4`, `objectKey` (Task 3)
- Produces: `List<int> encryptObjectBody(List<int> body, List<int> objectKey)`; `String encryptionDictionary({required List<int> ownerValue, required List<int> userValue, required int permissions})`

- [ ] **Step 1: Add the failing tests**

Append to `test/domain/pdf/pdf_encryption_test.dart`:
```dart
  group('encryptObjectBody', () {
    final key = List<int>.generate(10, (i) => i + 1);

    List<int> encrypt(String body) =>
        encryptObjectBody(latin1.encode(body), key);

    test('a body with no strings or streams is unchanged', () {
      const body = '<< /Type /Page /MediaBox [0 0 595 842] >>';
      expect(latin1.decode(encrypt(body)), body);
    });

    // A document whose streams are encrypted but whose strings are not still
    // opens and still renders - and leaks every annotation's text.
    test('a literal string is encrypted', () {
      const body = '<< /Type /Annot /Contents (secret words) >>';
      final out = latin1.decode(encrypt(body));

      expect(out, isNot(contains('secret words')));
      expect(out, startsWith('<< /Type /Annot /Contents ('));
    });

    test('a hexadecimal string is encrypted', () {
      const body = '<< /ID <deadbeef> >>';
      expect(latin1.decode(encrypt(body)), isNot(contains('deadbeef')));
    });

    test('stream data is encrypted', () {
      const payload = 'q 1 0 0 RG Q';
      final body =
          '<< /Length ${payload.length} >>\nstream\n$payload\nendstream';
      expect(latin1.decode(encrypt(body)), isNot(contains(payload)));
    });

    test('the dictionary around a stream survives', () {
      const payload = 'q Q';
      final body =
          '<< /Type /XObject /Length ${payload.length} >>\n'
          'stream\n$payload\nendstream';
      final out = latin1.decode(encrypt(body));

      expect(out, contains('/Type /XObject'));
      expect(out, contains('stream'));
      expect(out, contains('endstream'));
    });

    test('encryption is reversible with the same key', () {
      const payload = 'q 1 0 0 RG Q';
      final body =
          '<< /Length ${payload.length} >>\nstream\n$payload\nendstream';
      final once = encryptObjectBody(latin1.encode(body), key);

      // RC4 is symmetric, so decrypting is the same operation.
      expect(latin1.decode(encryptObjectBody(once, key)), body);
    });
  });

  group('the encryption dictionary', () {
    test('matches the revision 2 shape PDFium already opens', () {
      final d = encryptionDictionary(
        ownerValue: List<int>.filled(32, 0xAB),
        userValue: List<int>.filled(32, 0xCD),
        permissions: -44,
      );

      expect(d, contains('/Filter /Standard'));
      expect(d, contains('/V 1'));
      expect(d, contains('/R 2'));
      expect(d, contains('/P -44'));
      expect(d, contains('/O <'));
      expect(d, contains('/U <'));
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/pdf/pdf_encryption_test.dart`
Expected: FAIL — `encryptObjectBody` is not defined

- [ ] **Step 3: Implement the body encryptor**

Append to `lib/domain/pdf/pdf_encryption.dart`:
```dart
/// Encrypts every literal string, hexadecimal string and stream inside a
/// single object's body, using that object's key.
///
/// RC4 is symmetric, so applying this twice with the same key returns the
/// original - which is what the round-trip test relies on.
///
/// The caller must NOT pass the /Encrypt dictionary or the document /ID: a
/// reader needs both in the clear before it can derive any key.
List<int> encryptObjectBody(List<int> body, List<int> objectKey) {
  final text = latin1.decode(body, allowInvalid: true);

  // A stream is handled whole, because its data is binary and must not be
  // scanned for string delimiters.
  final streamAt = text.indexOf('stream');
  if (streamAt >= 0) {
    var dataStart = streamAt + 'stream'.length;
    if (text.startsWith('\r\n', dataStart)) {
      dataStart += 2;
    } else if (text.startsWith('\n', dataStart)) {
      dataStart += 1;
    }
    final dataEnd = text.lastIndexOf('endstream');
    if (dataEnd > dataStart) {
      final head = _encryptStrings(text.substring(0, streamAt), objectKey);
      final data = body.sublist(dataStart, dataEnd);
      return <int>[
        ...latin1.encode(head),
        ...latin1.encode(text.substring(streamAt, dataStart)),
        ...rc4(objectKey, data),
        ...latin1.encode(text.substring(dataEnd)),
      ];
    }
  }

  return latin1.encode(_encryptStrings(text, objectKey));
}

/// Encrypts the literal and hexadecimal strings in a dictionary fragment.
String _encryptStrings(String text, List<int> key) {
  var out = text.replaceAllMapped(RegExp(r'\(([^()]*)\)'), (m) {
    final encrypted = rc4(key, latin1.encode(m.group(1)!));
    return '(${_escape(latin1.decode(encrypted))})';
  });

  // hexString already wraps its output in angle brackets, so return it as-is.
  out = out.replaceAllMapped(
    RegExp(r'<([0-9A-Fa-f]+)>'),
    (m) => hexString(rc4(key, _fromHex(m.group(1)!))),
  );

  return out;
}

/// Escapes the characters that would end a PDF literal string early.
String _escape(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('(', r'\(')
    .replaceAll(')', r'\)');

List<int> _fromHex(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
```

- [ ] **Step 4: Implement the dictionary**

`lib/domain/pdf/pdf_encryption_dictionary.dart`:
```dart
import 'package:folio/domain/pdf/pdf_encryption.dart';

/// The standard security handler dictionary, revision 2.
///
/// This shape is not a guess: it matches `encrypted_user_pw.pdf`, a fixture
/// PDFium opens today.
String encryptionDictionary({
  required List<int> ownerValue,
  required List<int> userValue,
  required int permissions,
}) =>
    '<< /Filter /Standard /V 1 /R 2 '
    '/O ${hexString(ownerValue)} '
    '/U ${hexString(userValue)} '
    '/P $permissions >>';
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/domain/pdf/pdf_encryption_test.dart`
Expected: PASS — the existing vectors plus 7 new.

- [ ] **Step 6: Mutation-test string encryption**

In `encryptObjectBody`, return the head unchanged: replace
`_encryptStrings(text.substring(0, streamAt), objectKey)` with
`text.substring(0, streamAt)`, and the final line with
`return latin1.encode(text);`. Run the test file.

Expected: `a literal string is encrypted` and `a hexadecimal string is encrypted` both FAIL. Revert. This is the mutation that matters most: a document with encrypted streams and clear strings opens, renders, and leaks every annotation's text.

- [ ] **Step 7: Commit**

```bash
dart format lib test && flutter analyze --fatal-infos && flutter test
git add -A
git commit -m "feat: encrypt an object's strings and streams

Streams are handled whole, because their data is binary and must not be
scanned for string delimiters. Strings are encrypted in the dictionary around
them.

Encrypting streams but not strings produces a document that opens, renders,
and leaks every annotation's text. There is a mutation for exactly that."
```

---

# Stage 3 — Wiring it together

Ends with: an encrypted document that opens with its password and renders identically.

---

### Task 5: Encrypting on the way out, and verification

**Files:**
- Modify: `lib/domain/pdf/pdf_document_writer.dart`, `integration_test/object_layer_flow_test.dart`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`
- Test: `test/domain/pdf/pdf_document_writer_test.dart`

**Interfaces:**
- Consumes: `encryptObjectBody`, `encryptionDictionary`, `computeOwnerValue`, `computeEncryptionKey`, `computeUserValue`, `objectKey` (Tasks 3 and 4)
- Produces: `class PdfEncryption { const PdfEncryption({required String userPassword, int permissions = -44}); }` and `writePdfDocument(..., {PdfEncryption? encryption})`

- [ ] **Step 1: Add the failing writer tests**

Append to `test/domain/pdf/pdf_document_writer_test.dart`:
```dart
  group('encrypting', () {
    String encrypted() => latin1.decode(
      writePdfDocument(
        bytesOf(source),
        parsePdfObjects(bytesOf(source)),
        encryption: const PdfEncryption(userPassword: 'folio-test'),
      ),
    );

    test('the trailer references an /Encrypt dictionary', () {
      expect(encrypted(), contains('/Encrypt'));
    });

    test('the trailer carries an /ID', () {
      // Revision 2 derives its key from the first /ID element; without one a
      // reader cannot open the document at all.
      expect(encrypted(), contains('/ID [<'));
    });

    // The /Encrypt dictionary and the /ID are what a reader needs BEFORE it
    // can derive a key. Encrypting either produces a file nothing can open.
    test('the /Encrypt dictionary itself is not encrypted', () {
      final out = encrypted();

      expect(out, contains('/Filter /Standard'));
      expect(out, contains('/R 2'));
    });

    test('the password never appears in the output', () {
      expect(encrypted(), isNot(contains('folio-test')));
    });

    test('an unencrypted rewrite has no /Encrypt', () {
      expect(rewritten(), isNot(contains('/Encrypt')));
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/pdf/pdf_document_writer_test.dart`
Expected: FAIL — `PdfEncryption` is not defined

- [ ] **Step 3: Wire encryption into the writer**

In `lib/domain/pdf/pdf_document_writer.dart`, add the parameter object and the
hook:

```dart
/// How to encrypt a document on the way out.
class PdfEncryption {
  const PdfEncryption({required this.userPassword, this.permissions = -44});

  final String userPassword;

  /// The /P bit field. -44 is the value the existing fixtures use.
  final int permissions;
}
```

In `writePdfDocument`, hoist the object-number calculation above the loop —
Task 2 computes `highest` after it — and derive everything encryption needs in
one place:

```dart
  final highest = objects.map((o) => o.number).reduce((a, b) => a > b ? a : b);

  // The document /ID: revision 2 derives its key from the first element, so
  // one must exist and must NOT itself be encrypted. Deterministic, because a
  // random ID would make the writer untestable.
  final documentId = List<int>.generate(16, (i) => (i * 7 + 13) & 0xFF);

  final encryptNumber = highest + 1;
  List<int>? fileKey;
  List<int>? ownerValue;

  if (encryption != null) {
    ownerValue = computeOwnerValue(
      ownerPassword: encryption.userPassword,
      userPassword: encryption.userPassword,
    );
    fileKey = computeEncryptionKey(
      userPassword: encryption.userPassword,
      ownerValue: ownerValue,
      permissions: encryption.permissions,
      documentId: documentId,
    );
  }
```

Inside the object loop, encrypt each body with **its own** key:

```dart
    final body = fileKey == null
        ? o.body
        : encryptObjectBody(o.body, objectKey(fileKey, o.number, o.generation));
```

and write `body` rather than `o.body`.

After the loop, emit the `/Encrypt` object itself — **not** encrypted:

```dart
  if (encryption != null) {
    offsets[encryptNumber] = out.length;
    out.addAll(
      latin1.encode(
        '$encryptNumber 0 obj\n'
        '${encryptionDictionary(
          ownerValue: ownerValue!,
          userValue: computeUserValue(fileKey!),
          permissions: encryption.permissions,
        )}\nendobj\n',
      ),
    );
  }
```

The xref loop then runs to `encryption == null ? highest : encryptNumber`, and
the trailer gains both entries:

```dart
  final lastNumber = encryption == null ? highest : encryptNumber;
  …
      '<< /Size ${lastNumber + 1} /Root ${root.group(1)} ${root.group(2)} R'
      '${infos.isEmpty ? '' : ' /Info …'}'
      '${encryption == null ? '' : ' /Encrypt $encryptNumber 0 R'}'
      ' /ID [${hexString(documentId)} ${hexString(documentId)}] >>',
```

Add imports for `pdf_encryption.dart` and `pdf_encryption_dictionary.dart`.

- [ ] **Step 4: Run to verify it passes**

Run: `dart format lib test && flutter analyze --fatal-infos && flutter test`
Expected: all pass.

- [ ] **Step 5: Add the end-to-end encryption flows**

Append to `integration_test/object_layer_flow_test.dart`, asserting by
**rendering**:

1. **encrypt the real fixture, reopen it through `PdfrxEngine` with the
   password, render page 0, and require the pixels to match the unencrypted
   render exactly.** This is the only assertion that proves the pipeline: it
   fails if any key, any string, or any stream is wrong;
2. opening the encrypted document with the **wrong** password produces a typed
   failure rather than a crash — `PdfrxEngine.open` takes a
   `passwordProvider`, so supply one returning the wrong password and expect
   the documented failure;
3. the encrypted document still reports three pages once open;
4. the original bytes are unchanged.

- [ ] **Step 6: Run on the iOS simulator**

```bash
flutter test integration_test/all_tests.dart -d DFC5606D-37F0-4176-A73D-B8214C7F820F
```

Expected: all pass, including every earlier suite.

- [ ] **Step 7: Prove the pipeline assertion bites, twice**

First, in `writePdfDocument`, use the file key for every object instead of a
per-object key: `encryptObjectBody(o.body, fileKey)`. Re-run the flow file.

Expected: the encrypted-render test FAILS — the document will not open, or
renders wrongly. Revert.

Then, in `encryptObjectBody`, skip string encryption as in Task 4's mutation.
Re-run.

Expected: the encrypted-render test FAILS. Revert.

If either passes, the assertion is measuring nothing and must be strengthened
before this slice ships — four earlier slices shipped assertions that did
exactly that.

- [ ] **Step 8: Run on the Android emulator**

```bash
flutter emulators --launch pixel_api35
flutter test integration_test/all_tests.dart -d emulator-5554
```

Expected: all pass. If a test times out, check the emulator's health before
touching a bound: a degraded emulator has taken 31 seconds to open a 1.5 KB
document, where a fresh one takes about 50 ms.

- [ ] **Step 9: Verify the architectural guards still hold**

```bash
grep -nE "^\s+Future<.*> (write|save|export|materialise)" lib/domain/engine/pdf_engine.dart
grep -rn "userPassword" lib/ | grep -iE "print|log|debugPrint"
```

Expected: no matches for either. The second is the check that a password never
reaches a log.

- [ ] **Step 10: Update the documentation**

- `ARCHITECTURE.md` — that Folio now has two write models, when each applies,
  and why encryption forces the second; that the round-trip is verified at zero
  pixels; that `/Encrypt` and `/ID` are never encrypted.
- `TESTING.md` — refresh counts and the date.
- `FEATURES.md` — **unchanged**. Nothing user-visible ships in this slice, and
  saying otherwise would be the misrepresentation this sequencing exists to
  avoid.

- [ ] **Step 11: Full verification and push**

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed lib test integration_test scripts
flutter test --coverage
dart run scripts/check_licenses.dart
git add -A && git commit -m "feat: encrypt a document on the way out of the object layer

Every string and stream is encrypted with its own object key. The /Encrypt
dictionary and the document /ID are left in the clear, because a reader needs
both before it can derive a key.

Verified end to end: an encrypted document reopens with its password and
renders pixel-identical to the unencrypted original."
git push -u origin feature/sp5a-object-layer
gh pr create --base develop --title "SP-5a: object layer and encryption pipeline"
```

Confirm all four CI jobs pass, including `build-windows`. If jobs sit queued
with **zero steps**, that is a GitHub runner outage rather than a code failure:
`gh pr close N && gh pr reopen N` forces a fresh run once runners recover.

---

## Definition of done

- [ ] A document rewritten without encryption renders identically — zero pixels
- [ ] An encrypted document opens with its password and renders identically
- [ ] The wrong password fails cleanly
- [ ] Strings and streams are both encrypted, proven by mutation
- [ ] Per-object keys are used, proven by mutation
- [ ] The password never appears in the output or in any log
- [ ] `scripts/` imports the moved encryption module rather than owning it
- [ ] No user-facing encryption action exists
- [ ] `PdfEngine` still has no write method
- [ ] Integration passes on iOS simulator **and** Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] CI green on all four jobs including `build-windows`
- [ ] `ARCHITECTURE.md` and `TESTING.md` updated; `FEATURES.md` untouched

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

**Next:** SP-5b — AES-256 (R6) as the default handler, with `pointycastle`, and the user-facing "Protect with password" action that this slice deliberately withholds.
