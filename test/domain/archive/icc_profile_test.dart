import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/archive/icc_profile.dart';

/// A reader written from the ICC v2 specification, deliberately NOT sharing
/// code with the builder. Checking a profile with the same helpers that wrote
/// it proves the helpers agree with themselves and nothing else.
class _Profile {
  _Profile(this.bytes);

  final Uint8List bytes;

  int u32(int at) =>
      (bytes[at] << 24) |
      (bytes[at + 1] << 16) |
      (bytes[at + 2] << 8) |
      bytes[at + 3];

  int u16(int at) => (bytes[at] << 8) | bytes[at + 1];

  double fixed(int at) {
    final raw = u32(at);
    final signed = raw >= 0x80000000 ? raw - 0x100000000 : raw;
    return signed / 65536;
  }

  String signature(int at) => latin1.decode(bytes.sublist(at, at + 4));

  int get tagCount => u32(128);

  Map<String, ({int offset, int size})> get tags => {
    for (var i = 0; i < tagCount; i++)
      signature(132 + i * 12): (
        offset: u32(136 + i * 12),
        size: u32(140 + i * 12),
      ),
  };
}

void main() {
  late _Profile profile;

  setUp(() => profile = _Profile(buildSrgbIccProfile()));

  group('header', () {
    test('declares its own size, and that is the size it is', () {
      expect(profile.u32(0), profile.bytes.length);
    });

    // Without 'acsp' at offset 36 a file is not an ICC profile at all, and
    // every validator says exactly that and nothing more useful.
    test('carries the profile file signature', () {
      expect(profile.signature(36), 'acsp');
    });

    test('is a version 2 display profile for RGB', () {
      expect(profile.u32(8) >> 24, 2);
      expect(profile.signature(12), 'mntr');
      expect(profile.signature(16), 'RGB ');
      expect(profile.signature(20), 'XYZ ');
    });

    // The profile connection space is defined at D50. A profile that declares
    // a different illuminant is wrong in a way no viewer reports.
    test('declares the D50 illuminant', () {
      expect(profile.fixed(68), closeTo(0.9642, 0.0001));
      expect(profile.fixed(72), closeTo(1.0, 0.0001));
      expect(profile.fixed(76), closeTo(0.8249, 0.0001));
    });
  });

  group('tag table', () {
    test('has every tag a matrix profile needs', () {
      expect(
        profile.tags.keys,
        containsAll([
          'desc',
          'cprt',
          'wtpt',
          'rXYZ',
          'gXYZ',
          'bXYZ',
          'rTRC',
          'gTRC',
          'bTRC',
        ]),
      );
    });

    test('every tag lies inside the file, after the table', () {
      for (final tag in profile.tags.entries) {
        expect(
          tag.value.offset + tag.value.size,
          lessThanOrEqualTo(profile.bytes.length),
          reason: tag.key,
        );
        expect(
          tag.value.offset,
          greaterThanOrEqualTo(132 + profile.tagCount * 12),
          reason: tag.key,
        );
      }
    });

    // ICC requires tag data to begin on a four-byte boundary.
    test('every tag begins on a four-byte boundary', () {
      for (final tag in profile.tags.entries) {
        expect(tag.value.offset % 4, 0, reason: tag.key);
      }
    });

    test('every tag says what type it is', () {
      const expected = {
        'desc': 'desc',
        'cprt': 'text',
        'wtpt': 'XYZ ',
        'rXYZ': 'XYZ ',
        'gXYZ': 'XYZ ',
        'bXYZ': 'XYZ ',
        'rTRC': 'curv',
        'gTRC': 'curv',
        'bTRC': 'curv',
      };

      for (final tag in expected.entries) {
        expect(
          profile.signature(profile.tags[tag.key]!.offset),
          tag.value,
          reason: tag.key,
        );
      }
    });

    // Three identical curves may share one block of data, and two kilobytes
    // repeated three times is four kilobytes of nothing.
    test('the three tone curves share their data', () {
      expect(profile.tags['gTRC']!.offset, profile.tags['rTRC']!.offset);
      expect(profile.tags['bTRC']!.offset, profile.tags['rTRC']!.offset);
    });
  });

  group('colourants', () {
    test('are the sRGB primaries adapted to D50', () {
      final red = profile.tags['rXYZ']!.offset + 8;

      expect(profile.fixed(red), closeTo(0.4360, 0.0002));
      expect(profile.fixed(red + 4), closeTo(0.2225, 0.0002));
      expect(profile.fixed(red + 8), closeTo(0.0139, 0.0002));
    });

    // The three luminance components must sum to the white point's Y, or the
    // profile describes a display that cannot make white.
    test('sum to the white point', () {
      double y(String tag) => profile.fixed(profile.tags[tag]!.offset + 12);

      expect(y('rXYZ') + y('gXYZ') + y('bXYZ'), closeTo(1.0, 0.001));
    });
  });

  group('tone curve', () {
    List<int> curve() {
      final at = profile.tags['rTRC']!.offset;
      final count = profile.u32(at + 8);
      return [for (var i = 0; i < count; i++) profile.u16(at + 12 + i * 2)];
    }

    test('spans the whole range', () {
      final values = curve();

      expect(values.first, 0);
      expect(values.last, 65535);
    });

    test('never goes backwards', () {
      final values = curve();

      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]), reason: 'at $i');
      }
    });

    // The piecewise definition matters at the dark end, which on a scanned
    // page is most of the ink. A plain 2.2 gamma is visibly wrong there.
    test('follows the sRGB transfer function, not a plain gamma', () {
      final values = curve();

      for (final i in [10, 100, 500, 900]) {
        final u = i / (values.length - 1);
        final expected = u <= 0.04045
            ? u / 12.92
            : math.pow((u + 0.055) / 1.055, 2.4).toDouble();

        expect(values[i] / 65535, closeTo(expected, 0.0001), reason: 'at $i');
      }

      expect(
        values[10] / 65535,
        isNot(closeTo(math.pow(10 / 1023, 2.2).toDouble(), 0.0005)),
      );
    });
  });

  test('two profiles built at different times are identical', () {
    expect(buildSrgbIccProfile(), buildSrgbIccProfile());
  });
}
