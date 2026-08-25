# Features

Status is honest: "verified" means an automated test or a human exercised it on
that platform. A build passing is not verification.

## Legend

- ✅ implemented and verified on that platform
- 🟡 implemented, built, but not exercised on that platform
- ❌ not implemented
- — not applicable

## SP-1 — Foundation and Viewer

| Feature | iPhone | iPad | Android | Windows | Offline |
|---|---|---|---|---|---|
| Open / import PDF | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Library list | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Recents | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Favorites | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Search library | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Sort (name/date/size) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Rename / duplicate / delete | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Collections (data layer) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Save As / export | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Page rendering | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Zoom (pinch, buttons, double-tap) | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Page navigation + indicator | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Thumbnails panel | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Outline / bookmarks panel | ✅ | ✅ | ✅ | 🟡 | ✅ |
| In-document search + highlight | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Text selection + copy | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Copy restriction honoured | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Password-protected open | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Full screen | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Light / dark theme | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Responsive layout | ✅ | ✅ | ✅ | 🟡 | ✅ |
| Files-app integration | ✅ | ✅ | — | — | ✅ |

**Windows is 🟡 throughout.** It compiles and passes unit tests on CI; no human
or integration test has exercised it. See `LIMITATIONS.md`.

## Not in SP-1

Merge, split, reorder, rotate-and-save, annotations, signatures, scanner, OCR,
compression, encryption authoring, redaction, watermarks, metadata editing,
batch processing, automation rules, and printing are all ❌ — planned for
SP-2 through SP-9.
