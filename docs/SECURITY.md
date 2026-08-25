# Security

## PDFs are untrusted input

Every PDF is treated as hostile. Malformed, truncated and structurally invalid
files must fail with a friendly message, never a crash and never a raw stack
trace in the interface.

Verified by fixtures that are deliberately broken:

| Fixture | Asserted behaviour |
|---|---|
| `corrupt_truncated.pdf` | typed `AppFailure`, no crash |
| `malformed_xref.pdf` | typed `AppFailure`, no crash |
| `embedded_javascript.pdf` | opens; JavaScript is never executed |

## JavaScript is never executed

PDFs may embed JavaScript. Folio never runs it. The `embedded_javascript.pdf`
fixture carries a `/Names /JavaScript` entry and is asserted to open normally
without side effects.

## Encryption support

**Folio can read encrypted PDFs. It cannot create them.** Authoring encryption
arrives in SP-5.

Reading is provided by PDFium and covers the standard security handler. Verified
against a hand-generated revision-2 (RC4, 40-bit) document: the password prompt
appears, a correct password decrypts to the original content, a wrong password
re-prompts, and cancelling yields a typed failure.

**No claims are made about the strength of PDF encryption itself.** The PDF
standard security handler's older revisions are weak by modern standards. Folio
does not describe any of this as "military-grade" or equivalent.

## Document permissions

PDF permission flags (`/P`) are read and respected where the platform enforces
them. A document that forbids copying reports `allowsCopying == false`, and
pdfrx's selection layer refuses to place its text on the clipboard.

Permission flags are an author's request, not a security boundary — any tool
with the file can ignore them. Folio honours them; it does not pretend they are
enforcement.

## Passwords

A password entered to open a document is passed straight to the engine. It is
never logged, never persisted, and never written to disk.

## Network

The application makes no network requests. There is no backend, no telemetry,
no crash reporting service, and no analytics.
