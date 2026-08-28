import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/office/zip_writer.dart';

/// A reader written from APPNOTE, deliberately not sharing code with the
/// writer. Checking an archive with the same helpers that built it proves the
/// helpers agree with themselves.
class _Zip {
  _Zip(this.bytes);

  final Uint8List bytes;

  int u16(int at) => bytes[at] | (bytes[at + 1] << 8);
  int u32(int at) =>
      bytes[at] |
      (bytes[at + 1] << 8) |
      (bytes[at + 2] << 16) |
      (bytes[at + 3] << 24);

  /// The end-of-central-directory record, found by scanning back for its
  /// signature the way every reader does.
  int get _eocd {
    for (var at = bytes.length - 22; at >= 0; at--) {
      if (u32(at) == 0x06054b50) return at;
    }
    throw StateError('no end of central directory');
  }

  int get entryCount => u16(_eocd + 10);
  int get directoryOffset => u32(_eocd + 16);

  /// Every entry, read through the CENTRAL DIRECTORY rather than by walking
  /// the file: that is how a reader finds them, and an archive whose directory
  /// disagrees with its contents opens empty.
  Map<String, List<int>> get files {
    final out = <String, List<int>>{};
    var at = directoryOffset;

    for (var i = 0; i < entryCount; i++) {
      final nameLength = u16(at + 28);
      final extraLength = u16(at + 30);
      final commentLength = u16(at + 32);
      final localAt = u32(at + 42);
      final name = latin1.decode(bytes.sublist(at + 46, at + 46 + nameLength));

      final method = u16(localAt + 8);
      final compressed = u32(localAt + 18);
      final localName = u16(localAt + 26);
      final localExtra = u16(localAt + 28);
      final start = localAt + 30 + localName + localExtra;
      final data = bytes.sublist(start, start + compressed);

      out[name] = method == 0 ? data : ZLibCodec(raw: true).decode(data);

      at += 46 + nameLength + extraLength + commentLength;
    }

    return out;
  }

  /// The compression method recorded for an entry: 0 stored, 8 deflated.
  int methodOf(String name) {
    var at = directoryOffset;
    for (var i = 0; i < entryCount; i++) {
      final nameLength = u16(at + 28);
      if (latin1.decode(bytes.sublist(at + 46, at + 46 + nameLength)) == name) {
        return u16(at + 10);
      }
      at += 46 + nameLength + u16(at + 30) + u16(at + 32);
    }
    throw StateError('no entry $name');
  }

  int crcOf(String name) {
    var at = directoryOffset;
    for (var i = 0; i < entryCount; i++) {
      final nameLength = u16(at + 28);
      if (latin1.decode(bytes.sublist(at + 46, at + 46 + nameLength)) == name) {
        return u32(at + 16);
      }
      at += 46 + nameLength + u16(at + 30) + u16(at + 32);
    }
    throw StateError('no entry $name');
  }
}

void main() {
  group('crc32', () {
    // The published check value: the CRC of "123456789".
    test('matches the standard check value', () {
      expect(crc32(latin1.encode('123456789')), 0xCBF43926);
    });

    test('an empty input has a zero checksum', () {
      expect(crc32([]), 0);
    });

    test('a single byte matches the published table entry', () {
      expect(crc32([0]), 0xD202EF8D);
    });
  });

  group('writeZip', () {
    test('an entry comes back out as it went in', () {
      final zip = _Zip(
        writeZip([
          ZipEntry(name: 'hello.txt', bytes: latin1.encode('Hello, Priya')),
        ]),
      );

      expect(latin1.decode(zip.files['hello.txt']!), 'Hello, Priya');
    });

    test('several entries all come back', () {
      final zip = _Zip(
        writeZip([
          ZipEntry(name: 'a.xml', bytes: latin1.encode('<a/>')),
          ZipEntry(name: 'b/c.xml', bytes: latin1.encode('<c/>')),
          ZipEntry(name: 'd.txt', bytes: latin1.encode('plain')),
        ]),
      );

      expect(zip.entryCount, 3);
      expect(zip.files.keys, ['a.xml', 'b/c.xml', 'd.txt']);
    });

    // Compressible data must actually be compressed, or the format is only
    // accidentally a ZIP.
    test('repetitive data is deflated', () {
      final text = latin1.encode('the same sentence over and over. ' * 50);
      final bytes = writeZip([ZipEntry(name: 'r.txt', bytes: text)]);

      expect(bytes.length, lessThan(text.length));
      expect(latin1.decode(_Zip(bytes).files['r.txt']!), latin1.decode(text));
    });

    // Deflating a single byte produces three. The content survives either
    // way, so a round trip cannot see this - the recorded method can.
    test('data that would grow is stored instead', () {
      final zip = _Zip(
        writeZip([
          ZipEntry(name: 'x', bytes: [7]),
        ]),
      );

      expect(zip.files['x'], [7]);
      expect(zip.methodOf('x'), 0);
    });

    test('data that shrinks is marked as deflated', () {
      final zip = _Zip(
        writeZip([ZipEntry(name: 'r', bytes: latin1.encode('repeat ' * 100))]),
      );

      expect(zip.methodOf('r'), 8);
    });

    test('a checksum is recorded, and it is the right one', () {
      final data = latin1.encode('checksummed');
      final zip = _Zip(writeZip([ZipEntry(name: 'c.txt', bytes: data)]));

      expect(zip.crcOf('c.txt'), crc32(data));
    });

    test('the central directory points at each local header', () {
      final bytes = writeZip([
        ZipEntry(name: 'first.txt', bytes: latin1.encode('one')),
        ZipEntry(name: 'second.txt', bytes: latin1.encode('two')),
      ]);
      final zip = _Zip(bytes);

      var at = zip.directoryOffset;
      for (var i = 0; i < 2; i++) {
        final localAt = zip.u32(at + 42);

        expect(zip.u32(localAt), 0x04034b50, reason: 'entry $i');
        at += 46 + zip.u16(at + 28) + zip.u16(at + 30) + zip.u16(at + 32);
      }
    });

    test('bytes outside Latin-1 survive the round trip', () {
      final data = utf8.encode('नमस्ते — Folio');
      final zip = _Zip(writeZip([ZipEntry(name: 'u.txt', bytes: data)]));

      expect(utf8.decode(zip.files['u.txt']!), 'नमस्ते — Folio');
    });

    test('an empty archive is still a valid one', () {
      final zip = _Zip(writeZip([]));

      expect(zip.entryCount, 0);
    });

    test('an empty file inside an archive is fine', () {
      final zip = _Zip(writeZip([const ZipEntry(name: 'empty', bytes: [])]));

      expect(zip.files['empty'], isEmpty);
    });
  });

  // The strongest check available on the host: an implementation nobody here
  // wrote. A reader of my own can share a misunderstanding with the writer;
  // Python's cannot.
  group('read by something that is not this code', () {
    late Directory dir;

    setUp(() async => dir = await Directory.systemTemp.createTemp('zip'));
    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('python opens the archive and agrees about its contents', () async {
      final path = '${dir.path}/probe.zip';
      await File(path).writeAsBytes(
        writeZip([
          ZipEntry(name: '[Content_Types].xml', bytes: latin1.encode('<t/>')),
          ZipEntry(
            name: 'word/document.xml',
            bytes: utf8.encode('<w:document>नमस्ते</w:document>'),
          ),
        ]),
      );

      final result = await Process.run('python3', [
        '-c',
        'import zipfile,sys\n'
            'z=zipfile.ZipFile(sys.argv[1])\n'
            'bad=z.testzip()\n'
            'assert bad is None, bad\n'
            'print(",".join(z.namelist()))\n'
            'print(z.read("word/document.xml").decode())',
        path,
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('[Content_Types].xml,word/document.xml'));
      expect(result.stdout, contains('नमस्ते'));
    });
  });
}
