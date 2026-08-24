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
