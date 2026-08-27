import 'dart:typed_data';

/// A compressed document, and what it saved.
///
/// The compression is done ONCE. The saving is then the real difference in
/// bytes rather than a prediction, because a per-object estimate cannot model
/// the rewrite's own overhead - a fresh cross-reference table, an /ID, free
/// entries where objects were dropped - and an estimate shown to a user must
/// never promise more than it delivers.
///
/// [bytes] is kept so that accepting the result costs nothing further.
class CompressionResult {
  const CompressionResult({
    required this.bytes,
    required this.originalBytes,
    required this.duplicateBytes,
    required this.orphanedBytes,
    required this.deflatableBytes,
  });

  final Uint8List bytes;
  final int originalBytes;

  /// Bytes held by objects byte-identical to an earlier one. The dominant
  /// saving in practice: merging documents duplicates every shared font and
  /// image, and a merged set of five bank statements measured 37% duplicate.
  final int duplicateBytes;

  /// Bytes held by objects nothing refers to. These accumulate across
  /// incremental updates.
  final int orphanedBytes;

  /// Net bytes deflating uncompressed streams saves, after paying for the
  /// `/Filter` declaration. Near zero on most real documents, which arrive
  /// already compressed.
  final int deflatableBytes;

  int get compressedBytes => bytes.length;

  /// Exact, not predicted.
  int get savedBytes => originalBytes - compressedBytes;

  double get savedFraction =>
      originalBytes == 0 ? 0 : savedBytes / originalBytes;

  /// Below this, compressing is not worth a new document in the library.
  ///
  /// Either condition suffices: 2% of a 20 MB file is worth having, and so is
  /// 40 KB off a 60 KB file. Requiring both would refuse each of those.
  bool get worthDoing =>
      savedBytes > 0 && (savedFraction >= 0.02 || savedBytes >= 50 * 1024);
}
