@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/engine/pdf_engine.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/pdf/pdf_document_writer.dart';
import 'package:folio/domain/pdf/pdf_object.dart';
import 'package:folio/domain/pdf/pdf_permissions.dart' as folio;
import 'package:folio/engine/pdfrx_engine.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'fixture_helper.dart';

// Asymmetric on purpose: printing denied, copying allowed. A symmetric set
// would pass even if two bits were swapped.
const _restrictions = folio.PdfPermissions(printing: false, modifying: false);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  late Directory root;
  late PdfrxEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('objlayer');
    engine = PdfrxEngine();
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<PdfDocumentHandle> open(List<int> bytes, String name) async {
    final f = File('${root.path}/$name.pdf')..writeAsBytesSync(bytes);
    return engine.open(FileSource(f.path));
  }

  Future<List<int>> renderBytes(List<int> bytes, String name) async {
    final h = await open(bytes, name);
    final px = (await engine.renderPage(
      h,
      0,
      targetWidthPx: 400,
      targetHeightPx: 566,
    )).bgraPixels;
    await engine.close(h);
    return px;
  }

  int diff(List<int> a, List<int> b) {
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) n++;
    }
    return n;
  }

  group('object layer', () {
    test('a rewritten document renders identically', () async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();

      final rebuilt = writePdfDocument(original, parsePdfObjects(original));

      final before = await renderBytes(original, 'before');
      final after = await renderBytes(rebuilt, 'after');

      expect(
        diff(before, after),
        0,
        reason: 'a rewrite must not change a single pixel',
      );
    });

    test('a rewritten document still reports its pages', () async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();
      final rebuilt = writePdfDocument(original, parsePdfObjects(original));

      final h = await open(rebuilt, 'pages');
      expect(h.pageCount, 3);
      await engine.close(h);
    });

    // A corrupted rewrite can still render a blank page. Text surviving is
    // the cheapest proof the content streams came through intact.
    test('text still extracts from a rewritten document', () async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();
      final rebuilt = writePdfDocument(original, parsePdfObjects(original));

      final h = await open(rebuilt, 'text');
      final text = await engine.extractText(h, 0);
      await engine.close(h);

      expect(text!.fullText, contains('Confidential'));
    });
  });

  group('encryption', () {
    Future<(List<int> plain, List<int> secured)> build() async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();
      final objects = parsePdfObjects(original);

      return (
        writePdfDocument(original, objects),
        writePdfDocument(
          original,
          objects,
          encryption: const PdfEncryption(userPassword: 'folio-test'),
        ),
      );
    }

    // THE assertion. It fails if any key, any string or any stream is wrong,
    // and it is the only one that proves the pipeline rather than the bytes.
    test(
      'an encrypted document opens with its password and renders the same',
      () async {
        final (plain, secured) = await build();
        final expected = await renderBytes(plain, 'plain');

        final f = File('${root.path}/secured.pdf')..writeAsBytesSync(secured);
        final h = await engine.open(
          FileSource(f.path),
          onPasswordRequired: () async => 'folio-test',
        );
        final actual = (await engine.renderPage(
          h,
          0,
          targetWidthPx: 400,
          targetHeightPx: 566,
        )).bgraPixels;
        await engine.close(h);

        expect(
          diff(expected, actual),
          0,
          reason: 'encryption must not change what the page looks like',
        );
      },
    );

    group('owner password and permissions', () {
      Future<List<int>> restricted() async {
        final original = await File(
          await fixturePath('sample_3page.pdf'),
        ).readAsBytes();

        return writePdfDocument(
          original,
          parsePdfObjects(original),
          encryption: PdfEncryption(
            userPassword: 'reader-pw',
            ownerPassword: 'author-pw',
            permissions: _restrictions.bits,
          ),
        );
      }

      Future<List<int>> renderWith(String password, String name) async {
        final f = File('${root.path}/$name.pdf')
          ..writeAsBytesSync(await restricted());
        final h = await engine.open(
          FileSource(f.path),
          onPasswordRequired: () async => password,
        );
        final pixels = (await engine.renderPage(
          h,
          0,
          targetWidthPx: 400,
          targetHeightPx: 566,
        )).bgraPixels;
        await engine.close(h);
        return pixels;
      }

      // Both passwords must open the SAME document. A reader that accepts one
      // and rejects the other means the two entries disagree about the file
      // key, which is the failure this whole slice risks.
      test('both the user and the owner password open the document', () async {
        final asUser = await renderWith('reader-pw', 'as-user');
        final asOwner = await renderWith('author-pw', 'as-owner');

        expect(diff(asUser, asOwner), 0);
      });

      test('a restricted document still renders like the original', () async {
        final original = await File(
          await fixturePath('sample_3page.pdf'),
        ).readAsBytes();
        final expected = await renderBytes(
          writePdfDocument(original, parsePdfObjects(original)),
          'plain-restricted',
        );

        expect(
          diff(expected, await renderWith('reader-pw', 'restricted-render')),
          0,
          reason: 'restrictions govern what a reader may DO, not what it shows',
        );
      });

      // The one place /P is read back by a real reader rather than by our own
      // code. It compares the raw integer, not a reader's named getters:
      // pdfrx labels bit 4 \"copying\" and bit 16 \"printing\", which is the
      // reverse of ISO 32000-1 Table 22, so its names cannot be trusted here.
      test('the reader reports the restrictions that were asked for', () async {
        final f = File('${root.path}/perm-readback.pdf')
          ..writeAsBytesSync(await restricted());
        final h = await engine.open(
          FileSource(f.path),
          onPasswordRequired: () async => 'reader-pw',
        );
        final bits = h.permissionBits;
        await engine.close(h);

        // A reader that does not surface permissions at all tells us nothing,
        // and pretending otherwise would be the fake assertion this project
        // keeps finding. Only assert when there is something to assert on.
        if (bits == null) {
          markTestSkipped('this reader does not expose /P');
          return;
        }
        expect(bits.toSigned(32), _restrictions.bits);
      });
    });

    test('the wrong password fails cleanly', () async {
      final (_, secured) = await build();
      final f = File('${root.path}/wrong.pdf')..writeAsBytesSync(secured);

      // The callback is invoked REPEATEDLY until it succeeds or gives up.
      // Returning a wrong password forever retries forever; returning null is
      // how a caller says "I have no more passwords".
      var attempts = 0;
      await expectLater(
        engine.open(
          FileSource(f.path),
          onPasswordRequired: () async =>
              attempts++ == 0 ? 'not-the-password' : null,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(attempts, greaterThan(1), reason: 'it should have retried once');
    });

    // The render assertion cannot see this: sample_3page.pdf has no literal
    // strings in its dictionaries, so leaving them in the clear changes
    // nothing on screen. with_metadata.pdf carries /Title and /Author, which
    // is exactly the text a half-encrypted document leaks.
    test('dictionary strings do not survive in the clear', () async {
      final original = await File(
        await fixturePath('with_metadata.pdf'),
      ).readAsBytes();
      final plain = latin1.decode(original, allowInvalid: true);
      final title = RegExp(r'/Title\s*\(([^)]+)\)').firstMatch(plain);
      expect(title, isNotNull, reason: 'the fixture should carry a title');

      final secured = writePdfDocument(
        original,
        parsePdfObjects(original),
        encryption: const PdfEncryption(userPassword: 'folio-test'),
      );

      expect(
        latin1.decode(secured, allowInvalid: true),
        isNot(contains(title!.group(1)!)),
        reason: 'the title must not be readable in an encrypted document',
      );
    });

    test('an encrypted document still reports its pages', () async {
      final (_, secured) = await build();
      final f = File('${root.path}/pages.pdf')..writeAsBytesSync(secured);

      final h = await engine.open(
        FileSource(f.path),
        onPasswordRequired: () async => 'folio-test',
      );
      expect(h.pageCount, 3);
      await engine.close(h);
    });
  });

  group('AES-256', () {
    Future<(List<int> plain, List<int> secured)> build() async {
      final original = await File(
        await fixturePath('sample_3page.pdf'),
      ).readAsBytes();
      final objects = parsePdfObjects(original);

      return (
        writePdfDocument(original, objects),
        writePdfDocument(
          original,
          objects,
          encryption: const PdfEncryption(userPassword: 'folio-test'),
        ),
      );
    }

    // THE assertion for this slice. R6 has a lot of moving parts - the 2.B
    // hash, /U, /UE, /O, /OE, /Perms, and AES-CBC per value - and every one of
    // them being right is the only way this passes.
    test(
      'an AES-256 document opens with its password and renders the same',
      () async {
        final (plain, secured) = await build();
        final expected = await renderBytes(plain, 'aes-plain');

        final f = File('${root.path}/aes.pdf')..writeAsBytesSync(secured);
        final h = await engine.open(
          FileSource(f.path),
          onPasswordRequired: () async => 'folio-test',
        );
        final actual = (await engine.renderPage(
          h,
          0,
          targetWidthPx: 400,
          targetHeightPx: 566,
        )).bgraPixels;
        await engine.close(h);

        expect(diff(expected, actual), 0);
      },
    );

    test('it declares AES-256 rather than RC4', () async {
      final (_, secured) = await build();
      final text = latin1.decode(secured, allowInvalid: true);

      expect(text, contains('/AESV3'));
      expect(text, contains('/V 5'));
      expect(text, contains('/R 6'));
    });

    test('the wrong password fails cleanly', () async {
      final (_, secured) = await build();
      final f = File('${root.path}/aes-wrong.pdf')..writeAsBytesSync(secured);

      var attempts = 0;
      await expectLater(
        engine.open(
          FileSource(f.path),
          onPasswordRequired: () async =>
              attempts++ == 0 ? 'not-the-password' : null,
        ),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
