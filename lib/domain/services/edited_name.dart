/// Names for documents produced by page operations.
///
/// Applying edits always creates a new library entry, so these run often and
/// must not accumulate suffixes: "(edited)" becomes "(edited 2)", not
/// "(edited) (edited)".
library;

final RegExp _editedSuffix = RegExp(r'^(.*?)\s*\(edited(?:\s+(\d+))?\)$');

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
