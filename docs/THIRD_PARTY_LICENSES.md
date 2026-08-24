# Third-Party Licenses

Every dependency is verified before adoption. Only permissive licences are
permitted: MIT, BSD, Apache-2.0. **No GPL, LGPL, AGPL, or SSPL.** No commercial
SDK.

## Rejected dependencies

### syncfusion_flutter_pdf — PERMANENTLY REJECTED

Its LICENSE requires either a Syncfusion Community License (gross revenue under
USD 1,000,000 and fewer than five developers) or a paid commercial licence, and
states the product may not be used without one. This conflicts with the project's
free/open-source requirement and with distributing the app freely.

It is the obvious Flutter answer for merge/split/encrypt/redact. Recorded here so
the decision is not silently revisited.

Also excluded: Adobe PDF SDK, PSPDFKit, Apryse/PDFTron, Foxit, Nitro, and any
paid OCR or analytics SDK.

---

## Runtime dependencies

### pdfrx 2.4.7
- **License:** MIT
- **Source:** https://github.com/espresso3389/pdfrx
- **Bundles:** PDFium (BSD-3-Clause, Google)
- **Copyleft obligations:** none
- **Notes:** builds via Dart native assets (`hook/`, `code_assets`)

### flutter_localizations (Flutter SDK)
- **License:** BSD-3-Clause
- **Copyleft obligations:** none

### intl
- **License:** BSD-3-Clause
- **Source:** https://github.com/dart-lang/i18n
- **Copyleft obligations:** none

### logging
- **License:** BSD-3-Clause
- **Source:** https://github.com/dart-lang/logging
- **Copyleft obligations:** none

### crypto
- **License:** BSD-3-Clause
- **Source:** https://github.com/dart-lang/crypto
- **Copyleft obligations:** none

### path_provider
- **License:** BSD-3-Clause (Flutter team)
- **Source:** https://github.com/flutter/packages
- **Copyleft obligations:** none

### path
- **License:** BSD-3-Clause
- **Source:** https://github.com/dart-lang/path
- **Copyleft obligations:** none

### cupertino_icons
- **License:** MIT
- **Source:** https://github.com/flutter/cupertino_icons
- **Copyleft obligations:** none

## Development dependencies

### flutter_lints
- **License:** BSD-3-Clause (Flutter team)
- **Copyleft obligations:** none

### drift 2.34.3 / drift_flutter 0.3.1
- **License:** MIT
- **Source:** https://github.com/simolus3/drift
- **Copyleft obligations:** none

### sqlite3 3.5.2 (transitive)
- **License:** MIT (Dart bindings); SQLite itself is public domain
- **Source:** https://github.com/simolus3/sqlite3.dart
- **Copyleft obligations:** none
- **Notes:** builds via Dart native assets (`hooks`, `code_assets`,
  `native_toolchain_c`). `sqlite3_flutter_libs` 0.6.0+eol resolves as an empty
  compatibility shim; the native build moved into `sqlite3` 3.x.
