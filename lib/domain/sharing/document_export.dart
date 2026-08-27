import 'dart:typed_data';

/// A document about to leave the device.
///
/// Deliberately a named thing rather than a bare byte array: printing and
/// sharing are the only two features in Folio where a document goes somewhere
/// it cannot be recalled from, and the name that travels with it is what tells
/// the user which document they actually sent.
class DocumentExport {
  const DocumentExport({
    required this.bytes,
    required this.displayName,
    required this.isProtected,
  });

  final Uint8List bytes;

  /// The library name, so the share sheet and print job say which document
  /// this is. Redaction and every other operation produce a NEW document
  /// alongside the original, so two similarly named files sit in the library
  /// and picking the wrong one is the realistic mistake.
  final String displayName;

  /// True when the document is encrypted.
  ///
  /// The operating system's print renderer needs the password, which Folio
  /// does not pass to it and could not pass safely. Printing is refused rather
  /// than handed over to fail somewhere the user cannot see why.
  final bool isProtected;

  /// A filename safe to hand to another application.
  ///
  /// Path separators and control characters are stripped: a display name is
  /// user-supplied text, and it becomes a filename the moment it is shared.
  String get fileName {
    final cleaned = displayName
        .replaceAll(RegExp('[\\\\/:*?"<>|\\x00-\\x1f]'), '_')
        .trim();

    if (cleaned.isEmpty) return 'document.pdf';
    return cleaned.toLowerCase().endsWith('.pdf') ? cleaned : '$cleaned.pdf';
  }
}

/// Whether [text] is an encrypted PDF.
///
/// Looks for /Encrypt in a trailer rather than anywhere in the file: the
/// string can appear inside a stream's compressed data by coincidence, and
/// refusing to print a document because of a byte pattern in an image would be
/// a puzzling failure.
bool looksEncrypted(String text) {
  for (final match in RegExp(r'trailer\s*<<').allMatches(text)) {
    final close = text.indexOf('>>', match.end);
    if (close < 0) continue;
    if (text.substring(match.end, close).contains('/Encrypt')) return true;
  }
  return false;
}
