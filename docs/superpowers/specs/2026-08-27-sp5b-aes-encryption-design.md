# SP-5b — AES-256 encryption and Protect with password

**Status:** approved, ready for implementation
**Date:** 2026-08-27
**Depends on:** SP-5a (object layer and the encryption pipeline).

## Problem

SP-5a built the full-file writer and proved the encryption pipeline with
RC4-40 — deliberately behind no user-facing action, because RC4 is not
protection worth offering.

This slice replaces the cipher with AES-256 and makes the feature reachable.

## Scope

**In:** the PDF 2.0 standard security handler, revision 6 (AES-256); a
**Protect with password** action in the viewer; the encrypted document saved
as a new document.

**Out:** owner password and permission flags, which are SP-5c. This slice
writes an owner value derived from the same password, so the document has one
password and no separate permissions story yet.

## Decisions

### Revision 6, not revision 5

R5 was an Adobe extension that a later erratum superseded; R6 is what ISO
32000-2 standardises and what current tools write. Writing R5 would mean
shipping a deprecated variant on purpose.

### The file key is used directly — there are no per-object keys

This is the opposite of R2, and it is easy to get wrong by analogy. In V5 the
file encryption key encrypts every string and stream directly; the per-object
key derivation that R2 requires does not exist. Applying it anyway produces a
document nothing can open.

### Each string and stream carries its own initialisation vector

AES-256-CBC with a random 16-byte IV, prepended to the ciphertext, and PKCS#7
padding. Reusing one IV across a document is a real cryptographic weakness,
not a stylistic choice.

### RC4 remains, unreachable

SP-5a's R2 implementation stays in the codebase and stays tested. It is the
reference the pipeline was proven against, and SP-5c decides whether it ever
becomes selectable for old readers. Nothing in the UI offers it.

### A wrong password must be indistinguishable from a corrupt file

Folio never says whether a password was *close*. The failure is the existing
typed `WrongPassword`, with no detail beyond that.

## Architecture

### `lib/domain/pdf/pdf_encryption_aes.dart` — new

```dart
/// Algorithm 2.B: the hardened hash R6 uses for both passwords.
List<int> hash2B(List<int> password, List<int> salt, List<int> userData);

/// Everything the /Encrypt dictionary needs for one password.
class AesEncryptionValues {
  final List<int> fileKey;   // 32 random bytes
  final List<int> u;         // 48 bytes
  final List<int> ue;        // 32 bytes
  final List<int> o;         // 48 bytes
  final List<int> oe;        // 32 bytes
  final List<int> perms;     // 16 bytes
}

AesEncryptionValues buildAesValues({
  required String password,
  required int permissions,
  required List<int> Function(int) randomBytes,
});

/// AES-256-CBC with a random IV prepended, PKCS#7 padded.
List<int> aesEncrypt(List<int> key, List<int> data, List<int> iv);
```

`randomBytes` is injected so tests are deterministic; production passes a
`Random.secure()`-backed generator.

### Changes

- `pdf_document_writer.dart` — `PdfEncryption` gains a handler; V5 uses the
  file key directly and emits the V5 dictionary.
- `pdf_encryption_dictionary.dart` — the V5/R6 dictionary alongside R2's.
- A repository and a viewer action, following the watermark slice's shape.

## Testing

Unit: `hash2B` is deterministic and 32 bytes; the values are the right widths;
`aesEncrypt` output is IV-prefixed and a multiple of 16; the V5 dictionary
carries `/AESV3`, `/StmF`, `/StrF`, `/UE`, `/OE`, `/Perms`.

Integration, the assertion that matters: **encrypt with AES-256, reopen with
the password through pdfrx, render, and require the pixels to match the
unencrypted original.** Plus a wrong password failing cleanly, and the source
byte-identical.

Mutations: use a per-object key as R2 does; reuse one IV for every string.

## Definition of done

- [ ] An AES-256 document opens with its password and renders identically
- [ ] The wrong password fails cleanly
- [ ] Per-object keys are NOT used, proven by mutation
- [ ] Each string and stream has its own IV, proven by mutation
- [ ] A "Protect with password" action exists and produces a new document
- [ ] Integration green on iOS simulator and Android emulator
- [ ] CI green on all four jobs; licence audit passes with pointycastle
- [ ] `FEATURES.md`, `LIMITATIONS.md`, `ARCHITECTURE.md`, `TESTING.md` updated
