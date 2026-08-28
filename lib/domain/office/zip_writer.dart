import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One file inside a ZIP archive.
class ZipEntry {
  const ZipEntry({required this.name, required this.bytes, this.store = false});

  /// The path inside the archive, always with forward slashes.
  final String name;

  final List<int> bytes;

  /// Stored rather than deflated. Only worth it for data that will not
  /// compress; everything Folio writes is XML, which compresses well.
  final bool store;
}

/// Writes a ZIP archive.
///
/// Every Office format is XML inside a ZIP, so this is the whole container
/// half of the job. It exists rather than a package because the alternative is
/// a dependency for two hundred lines of well-specified structure - and
/// because a malformed archive gives a file Word refuses to open at all,
/// which is a thing to be able to debug.
///
/// APPNOTE 6.3.3, the parts of it that a small archive needs: a local header
/// and data for each file, a central directory describing them, and an
/// end-of-central-directory record pointing at that.
Uint8List writeZip(List<ZipEntry> entries) {
  final out = <int>[];
  final directory = <int>[];

  for (final entry in entries) {
    final name = latin1.encode(entry.name);
    final raw = entry.bytes;
    // Raw deflate, not zlib: a ZIP entry carries the compressed stream with no
    // zlib header or checksum of its own. The two-byte header is enough to
    // make an archive unreadable.
    final deflated = entry.store
        ? raw
        : ZLibCodec(level: 9, raw: true).encode(raw);

    // Deflate makes small data bigger - a single byte becomes three. The
    // content survives either way, so this is size rather than correctness,
    // but an archive that grows what it compresses is a poor archive.
    final stored = entry.store || deflated.length >= raw.length;
    final data = stored ? raw : deflated;
    final crc = crc32(raw);
    final offset = out.length;

    out
      ..addAll(_uint32(0x04034b50))
      ..addAll(_uint16(20)) // version needed
      ..addAll(_uint16(0)) // flags
      ..addAll(_uint16(stored ? 0 : 8)) // method
      ..addAll(_uint16(0)) // modification time
      ..addAll(_uint16(0x21)) // modification date: 1980-01-01
      ..addAll(_uint32(crc))
      ..addAll(_uint32(data.length))
      ..addAll(_uint32(raw.length))
      ..addAll(_uint16(name.length))
      ..addAll(_uint16(0)) // extra field length
      ..addAll(name)
      ..addAll(data);

    directory
      ..addAll(_uint32(0x02014b50))
      ..addAll(_uint16(20)) // version made by
      ..addAll(_uint16(20)) // version needed
      ..addAll(_uint16(0))
      ..addAll(_uint16(stored ? 0 : 8))
      ..addAll(_uint16(0))
      ..addAll(_uint16(0x21))
      ..addAll(_uint32(crc))
      ..addAll(_uint32(data.length))
      ..addAll(_uint32(raw.length))
      ..addAll(_uint16(name.length))
      ..addAll(_uint16(0)) // extra
      ..addAll(_uint16(0)) // comment
      ..addAll(_uint16(0)) // disk number
      ..addAll(_uint16(0)) // internal attributes
      ..addAll(_uint32(0)) // external attributes
      ..addAll(_uint32(offset))
      ..addAll(name);
  }

  final directoryOffset = out.length;
  out
    ..addAll(directory)
    ..addAll(_uint32(0x06054b50))
    ..addAll(_uint16(0)) // this disk
    ..addAll(_uint16(0)) // disk with the directory
    ..addAll(_uint16(entries.length))
    ..addAll(_uint16(entries.length))
    ..addAll(_uint32(directory.length))
    ..addAll(_uint32(directoryOffset))
    ..addAll(_uint16(0)); // archive comment

  return Uint8List.fromList(out);
}

/// CRC-32 as ZIP defines it: the reflected polynomial 0xEDB88320, starting and
/// ending inverted.
///
/// A wrong checksum is the failure that costs the most time to find: every
/// reader opens the archive, reads the file, and only then refuses it.
int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;

  for (final byte in bytes) {
    crc ^= byte & 0xFF;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }

  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

List<int> _uint16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

List<int> _uint32(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];
