# SP-5a — Object layer and the encryption pipeline

**Status:** approved, ready for planning
**Date:** 2026-08-27
**Depends on:** SP-1 (PdfObjectIndex), SP-4a (page content writing).

## Problem

Every write Folio does today is a PDF **incremental update**: append, never
rewrite. That is what makes annotations, watermarks and metadata safe, and it
is why originals are never touched.

Encryption cannot work that way. Encrypting a document means encrypting every
string and every stream in it, which means every object must be re-emitted.
There is nothing to append.

This slice builds the full-file writer that makes that possible, and proves the
encryption pipeline end to end.

## Probed before designing

A throwaway 77-line Dart object model, on 2026-08-26, parsed every object out
of a real document, rebuilt the file from scratch with a fresh xref and
trailer, and PDFium rendered it with **zero pixels different**.

That is the evidence this is hand-written Dart rather than a cross-compiled
qpdf, which would mean C++20 plus zlib plus libjpeg across four toolchains
maintained indefinitely.

## Scope

**In:** a full-file writer; the RC4 encryption pipeline wired through it;
every string and stream encrypted with its per-object key; a document that
PDFium opens with a password and renders identically.

**Out, deliberately:**

- **Any user-facing feature.** No "Protect with password" button. See below.
- **AES-256.** SP-5b, once the pipeline is proven.
- **Owner password and permission flags.** SP-5c.
- **Compressing existing documents** and **redaction**, which the object layer
  also unblocks but which are separate features on their own evidence.

### This slice ships no button, on purpose

RC4-40 is not protection worth offering. Shipping a "password protect" action
backed by it would tell the user their document is secure when it is not.

So SP-5a lands the object layer and the pipeline with tests as its only
consumer. The feature becomes visible in SP-5b, when AES-256 replaces the
cipher against a pipeline already known to work.

**The risk of that sequencing, stated:** if SP-5b never lands, Folio sits on
encryption machinery no user can reach. That is the correct failure — better
unreachable than misrepresented.

### Why RC4 first rather than AES-256 first

`scripts/pdf_encrypt.dart` already implements ISO 32000-1 Algorithms 2, 3 and 4
— RC4, password padding, the file encryption key, `/O`, `/U` and per-object
keys — in 134 lines, with 155 lines of tests, producing fixtures PDFium opens
today.

Doing AES-256 first would mean debugging a brand-new full-file writer **and** a
brand-new cipher simultaneously, against a single failure signal: the document
will not open. With RC4 the cipher is already proven, so any failure is the
writer.

### Revision: R2, not R4

The existing code is **revision 2, RC4-40** — a five-byte key, `/U` by
Algorithm 4. It is not R4/128, which needs fifty MD5 iterations and Algorithm 5.

SP-5a uses R2 unchanged, because R2 is exactly what is proven and this slice
exists to test the writer, not the cipher. R2 is also the most widely readable
revision, which is the compatibility argument the RC4 handler exists for at
all. Whether the shipped RC4 option becomes R4/128 is decided in SP-5c, when it
first becomes reachable.

## Architecture

### `lib/domain/pdf/pdf_object.dart` — new

```dart
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

/// Every object in a document, in file order.
///
/// Honours `/Length` when skipping a stream, so binary data containing the
/// bytes `endobj` cannot end an object early.
List<PdfObject> parsePdfObjects(List<int> bytes);
```

### `lib/domain/pdf/pdf_document_writer.dart` — new

```dart
/// Rebuilds a complete PDF: header, every object, a fresh xref, a trailer.
///
/// No `/Prev`: this is a rewrite, not an incremental update.
Uint8List writePdfDocument(
  List<int> original,
  List<PdfObject> objects, {
  PdfEncryption? encryption,
});
```

When `encryption` is present the writer encrypts each object's strings and
streams with that object's key as it emits them, and adds `/Encrypt` to the
trailer. That single hook is the whole reason the rewrite exists.

### `lib/domain/pdf/pdf_encryption.dart` — new

`scripts/pdf_encrypt.dart` moves here, unchanged in behaviour, and the script
imports it rather than owning it. Its existing tests move with it. The
algorithms are proven; relocating them must not alter a single vector, which
the moved tests assert.

**Three files import it today, and one of them runs on device:**

| Importer | Why it matters |
|---|---|
| `scripts/make_fixtures.dart` | host-side fixture generation |
| `test/scripts/pdf_encrypt_test.dart` | the vectors that prove the move is behaviour-preserving |
| `integration_test/fixture_helper.dart` | **builds encrypted fixtures on the device** |

The third is the one to be careful with: integration tests generate their own
fixtures at runtime rather than shipping 2.5 MB of them in the bundle, so this
code already executes on iOS and Android. Moving it into `lib/` makes that
honest — device code should not be reaching into `scripts/` — but it means the
move is verified by the integration suite, not only by unit tests.

`buildEncryptedPdf` takes the algorithms as injected function parameters, so
the fixture builder itself needs no change at all. Only the three import sites
move.

Adds one thing the script never needed:

```dart
/// Encrypts every literal and hexadecimal string, and every stream, inside a
/// single object's body.
///
/// The /Encrypt dictionary itself and the document /ID are NEVER encrypted:
/// a reader needs both before it can derive a key.
List<int> encryptObjectBody(List<int> body, List<int> objectKey);
```

### `lib/domain/pdf/pdf_encryption_dictionary.dart` — new

Builds `<< /Filter /Standard /V 1 /R 2 /O <…> /U <…> /P … >>`, matching the
shape of the fixture PDFium already opens.

## Risks

**Strings are the easy thing to miss.** A document whose streams are encrypted
but whose strings are not will still open, still render, and be silently
wrong — text in annotations and metadata left in the clear. There is a
mutation for exactly this.

**Per-object keys are the second.** Encrypting everything with the file key
also produces a file that opens for some readers and not others. Mutation for
this too.

**The `/Encrypt` dictionary must not itself be encrypted**, nor the `/ID`.
Getting that wrong produces a document nothing can open, which at least fails
loudly.

## Testing

Unit:

- `parsePdfObjects` finds every object, including one whose stream contains the
  bytes `endobj`;
- the writer round-trips a document with no encryption and it still parses;
- the moved encryption vectors match the ones already asserted today;
- `encryptObjectBody` leaves a body with no strings or streams unchanged;
- the encryption dictionary matches the fixture's shape.

Integration — the only assertion that really matters:

- **encrypt a document, reopen it through pdfrx with the password, and render
  it: the pixels must match the unencrypted render exactly.** Anything less
  proves only that we wrote bytes;
- opening it with the wrong password fails as a typed failure, not a crash;
- a document rewritten without encryption renders identically to the original;
- the source document is byte-identical afterwards.

Mutations: skip string encryption; use the file key instead of per-object keys.

## Definition of done

- [ ] A document rewritten without encryption renders identically
- [ ] An encrypted document opens with its password and renders identically
- [ ] The wrong password fails cleanly
- [ ] Strings and streams are both encrypted, proven by mutation
- [ ] Per-object keys are used, proven by mutation
- [ ] `scripts/pdf_encrypt.dart` imports the moved code rather than duplicating it
- [ ] No user-facing encryption action exists yet
- [ ] `PdfEngine` still has no write method
- [ ] Integration green on iOS simulator and Android emulator
- [ ] `flutter analyze --fatal-infos` clean; licence audit passes
- [ ] All four CI jobs green, `build-windows` included
- [ ] `ARCHITECTURE.md` and `TESTING.md` updated; `FEATURES.md` unchanged,
      because nothing user-visible ships
