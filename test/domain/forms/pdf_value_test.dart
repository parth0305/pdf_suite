import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/forms/pdf_value.dart';

void main() {
  group('readValue', () {
    test('reads a literal string', () {
      expect(readValue('<< /V (Priya Menon) >>', 'V'), 'Priya Menon');
    });

    test('reads a name', () {
      expect(readValue('<< /V /Premium >>', 'V'), 'Premium');
    });

    test('reads a hex string', () {
      expect(readValue('<< /V <48656C6C6F> >>', 'V'), 'Hello');
    });

    // Anything outside Latin-1 reaches a PDF as UTF-16BE behind a byte-order
    // mark. Reading those bytes as Latin-1 gives mojibake that looks like data.
    test('reads UTF-16 behind a byte-order mark', () {
      expect(readValue('<< /V <FEFF0928092E0938094D0924> >>', 'V'), 'नमस्त');
    });

    test('an escaped bracket does not end the string early', () {
      expect(readValue(r'<< /V (Menon \(Ms\)) >>', 'V'), 'Menon (Ms)');
    });

    test('nested brackets are balanced', () {
      expect(readValue('<< /V (a (b) c) >>', 'V'), 'a (b) c');
    });

    test('an escaped newline becomes one', () {
      expect(readValue(r'<< /V (one\ntwo) >>', 'V'), 'one\ntwo');
    });

    test('a missing key has no value', () {
      expect(readValue('<< /T (name) >>', 'V'), isNull);
    });

    // /V and /Vertices start alike. Matching on the prefix reads the wrong one.
    test('a key that merely starts the same is not matched', () {
      expect(readValue('<< /Vertices [1 2] >>', 'V'), isNull);
    });

    test('a dictionary value is not mistaken for a hex string', () {
      expect(readValue('<< /V << /S /Thing >> >>', 'V'), isNull);
    });
  });

  group('readOptions', () {
    test('reads a plain list', () {
      expect(readOptions('/Opt [(India) (Nepal)]'), ['India', 'Nepal']);
    });

    // A choice may pair an export value with a label. A person picks from the
    // labels; the export value is what gets written back.
    test('a paired option shows the label', () {
      expect(readOptions('/Opt [[(IN) (India)] [(NP) (Nepal)]]'), [
        'India',
        'Nepal',
      ]);
    });

    test('a paired option exports the code', () {
      expect(exportValues('/Opt [[(IN) (India)] [(NP) (Nepal)]]'), [
        'IN',
        'NP',
      ]);
    });

    test('an unpaired option exports itself', () {
      expect(exportValues('/Opt [(India) (Nepal)]'), ['India', 'Nepal']);
    });

    test('no options at all', () {
      expect(readOptions('<< /FT /Ch >>'), isEmpty);
    });

    test('an option containing a bracket survives', () {
      expect(readOptions(r'/Opt [(India \(Bharat\))]'), ['India (Bharat)']);
    });
  });

  group('withEntry', () {
    test('adds an entry that is not there', () {
      expect(
        withEntry('<< /T (name) >>', 'V', '(Priya)'),
        contains('/V (Priya)'),
      );
    });

    test('replaces one that is', () {
      final out = withEntry('<< /V (old) /T (name) >>', 'V', '(new)');

      expect(out, contains('/V (new)'));
      expect(out, isNot(contains('old')));
      expect(out, contains('/T (name)'));
    });

    // `12 0 R` is ONE value. Stopping at the number leaves `0 R` behind as
    // though it were the next entry, and the dictionary is then corrupt.
    test('replaces a value that is an indirect reference', () {
      final out = withEntry(
        '<< /AP 12 0 R /T (name) >>',
        'AP',
        '<< /N 5 0 R >>',
      );

      expect(out, contains('/AP << /N 5 0 R >>'));
      expect(out, isNot(contains('12 0 R')));
      expect(out, isNot(contains('0 R /T')));
    });

    test('replaces a value that is a dictionary', () {
      final out = withEntry(
        '<< /AP << /N << /Off 1 0 R >> >> /T (name) >>',
        'AP',
        '<< /N 5 0 R >>',
      );

      expect(out, contains('/AP << /N 5 0 R >>'));
      expect(out, contains('/T (name)'));
      expect(out, isNot(contains('/Off')));
    });

    test('replaces a value that is an array', () {
      final out = withEntry('<< /Opt [(a) (b)] /T (n) >>', 'Opt', '[(c)]');

      expect(out, contains('/Opt [(c)]'));
      expect(out, isNot(contains('(a)')));
    });

    test('replaces a value that is a name', () {
      expect(
        withEntry('<< /AS /Off /T (n) >>', 'AS', '/On'),
        contains('/AS /On'),
      );
    });

    test('a bracket inside the old value does not end it early', () {
      final out = withEntry(r'<< /V (a \) b) /T (n) >>', 'V', '(new)');

      expect(out, contains('/T (n)'));
      expect(out, isNot(contains(' b)')));
    });

    test('an array holding a bracketed string is skipped whole', () {
      final out = withEntry(r'<< /Opt [(a\] b)] /T (n) >>', 'Opt', '[(c)]');

      expect(out, contains('/T (n)'));
      expect(out, contains('/Opt [(c)]'));
    });
  });
}
