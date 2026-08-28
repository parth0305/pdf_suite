/// Names for documents produced by page operations.
///
/// Applying edits always creates a new library entry, so these run often and
/// must not accumulate suffixes: "(edited)" becomes "(edited 2)", not
/// "(edited) (edited)".
library;

final RegExp _editedSuffix = RegExp(r'^(.*?)\s*\(edited(?:\s+(\d+))?\)$');
final RegExp _redactedSuffix = RegExp(r'^(.*?)\s*\(redacted(?:\s+(\d+))?\)$');
final RegExp _archivedSuffix = RegExp(r'^(.*?)\s*\(PDF/A(?:\s+(\d+))?\)$');

({String stem, String extension}) _split(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return (stem: name, extension: '');
  return (stem: name.substring(0, dot), extension: name.substring(dot));
}

String editedName(String original) {
  final parts = _split(original);
  final match = _editedSuffix.firstMatch(parts.stem);

  if (match == null) {
    return '${parts.stem} (edited)${parts.extension}';
  }

  final base = match.group(1)!;
  final current = int.tryParse(match.group(2) ?? '') ?? 1;
  return '$base (edited ${current + 1})${parts.extension}';
}

String extractedName(String original, int pageCount) {
  final parts = _split(original);
  final unit = pageCount == 1 ? 'page' : 'pages';
  return '${parts.stem} ($pageCount $unit)${parts.extension}';
}

String splitPartName(String original, int part) {
  final parts = _split(original);
  return '${parts.stem} (part $part)${parts.extension}';
}

/// Names the result of redacting [original].
///
/// Redaction always produces a new document, so the name has to say which is
/// which at a glance in the library. Redacting twice is plausible - a second
/// pass over a document someone already cleaned - so this counts up the way
/// [editedName] does rather than accumulating suffixes.
String redactedName(String original) {
  final parts = _split(original);
  final match = _redactedSuffix.firstMatch(parts.stem);

  if (match == null) {
    return '${parts.stem} (redacted)${parts.extension}';
  }

  final base = match.group(1)!;
  final current = int.tryParse(match.group(2) ?? '') ?? 1;
  return '$base (redacted ${current + 1})${parts.extension}';
}

/// Names the result of converting [original] for archiving.
///
/// The suffix says the FORMAT rather than the action, because that is what
/// someone filing it needs to know a year later.
String archivedName(String original) {
  final parts = _split(original);
  final match = _archivedSuffix.firstMatch(parts.stem);

  if (match == null) {
    return '${parts.stem} (PDF/A)${parts.extension}';
  }

  final base = match.group(1)!;
  final current = int.tryParse(match.group(2) ?? '') ?? 1;
  return '$base (PDF/A ${current + 1})${parts.extension}';
}
