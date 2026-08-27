import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/storage/safe_file_writer.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/automation_dao.dart';
import 'package:folio/data/local/library_dao.dart';
import 'package:folio/data/repositories/automation_repository_impl.dart';
import 'package:folio/data/repositories/library_repository_impl.dart';
import 'package:folio/domain/automation/automation_rule.dart';
import 'package:folio/domain/compression/compression_estimate.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/repositories/compression_repository.dart';
import 'package:folio/domain/repositories/ocr_repository.dart';
import 'package:folio/domain/repositories/watermark_repository.dart';
import 'package:folio/domain/watermark/watermark.dart';

/// Produces a real second library document, so replace-and-delete can be
/// observed against a real database rather than a mock.
class FakeCompression implements CompressionRepository {
  FakeCompression(this.library, {this.worth = true});

  final LibraryRepositoryImpl library;
  final bool worth;
  int analysed = 0;

  @override
  Future<CompressionResult> analyse(int documentId) async {
    analysed++;
    return CompressionResult(
      bytes: Uint8List.fromList(smallPdf('COMPRESSED')),
      originalBytes: 100000,
      duplicateBytes: 0,
      orphanedBytes: 0,
      deflatableBytes: 0,
    );
  }

  @override
  Future<LibraryDocument> save(int documentId, CompressionResult result) async {
    if (!worth) throw StateError('should not have been called');
    return _store(library, 'Compressed.pdf', 'COMPRESSED');
  }
}

class FakeOcr implements OcrRepository {
  FakeOcr(this.library, {this.fails = false});

  final LibraryRepositoryImpl library;
  final bool fails;
  int calls = 0;

  @override
  Future<LibraryDocument> recognise(int documentId) async {
    calls++;
    if (fails) throw ArgumentError('no text');
    return _store(library, 'Recognised.pdf', 'RECOGNISED');
  }
}

class FakeWatermark implements WatermarkRepository {
  FakeWatermark(this.library);

  final LibraryRepositoryImpl library;
  final marks = <String>[];

  @override
  Future<LibraryDocument> apply(int documentId, Watermark mark) async {
    marks.add(mark.text);
    return _store(library, 'Marked.pdf', 'MARKED');
  }
}

List<int> smallPdf(String tag) =>
    '%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n% $tag\n%%EOF\n'
        .codeUnits;

Future<LibraryDocument> _store(
  LibraryRepositoryImpl library,
  String name,
  String tag,
) async {
  final dir = await Directory.systemTemp.createTemp('auto_src');
  final f = File('${dir.path}/$name')..writeAsBytesSync(smallPdf(tag));
  return library.importFile(f.path, displayName: name);
}

/// What the mocked platform channel resolves a bookmark to. Set by the one
/// test that needs a document opened in place.
String mockResolvedPath = '';

void main() {
  // openInPlace captures a durable handle through a platform channel that
  // exists only on a real device. The fake hands back a bookmark so the
  // non-managed path can be exercised in a unit test at all.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.folio.app/handles'),
          (call) async => switch (call.method) {
            'createBookmark' => Uint8List.fromList([1, 2, 3]),
            'resolveBookmark' => mockResolvedPath,
            _ => null,
          },
        );
  });

  late AppDatabase db;
  late Directory root;
  late LibraryRepositoryImpl library;
  late AutomationDao dao;
  late FakeCompression compression;
  late FakeOcr ocr;
  late FakeWatermark watermark;
  late AutomationRepositoryImpl subject;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('auto');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      dao: LibraryDao(db),
      writer: SafeFileWriter(),
      libraryRoot: root,
    );
    dao = AutomationDao(db);
    compression = FakeCompression(library);
    ocr = FakeOcr(library);
    watermark = FakeWatermark(library);
    subject = AutomationRepositoryImpl(
      dao: dao,
      library: library,
      compression: compression,
      ocr: ocr,
      watermark: watermark,
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<LibraryDocument> imported({String name = 'Invoice.pdf'}) =>
      _store(library, name, 'ORIGINAL');

  group('storing rules', () {
    test('a rule round-trips', () async {
      await subject.add(
        action: AutomationAction.compress,
        nameContains: 'invoice',
        minSizeBytes: 500,
      );

      final rules = await subject.rules();
      expect(rules, hasLength(1));
      expect(rules.single.action, AutomationAction.compress);
      expect(rules.single.nameContains, 'invoice');
      expect(rules.single.minSizeBytes, 500);
      expect(rules.single.enabled, isTrue);
    });

    test('a rule can be disabled and re-enabled', () async {
      final rule = await subject.add(action: AutomationAction.compress);

      await subject.setEnabled(rule.id, enabled: false);
      expect((await subject.rules()).single.enabled, isFalse);

      await subject.setEnabled(rule.id, enabled: true);
      expect((await subject.rules()).single.enabled, isTrue);
    });

    test('a rule can be removed', () async {
      final rule = await subject.add(action: AutomationAction.compress);
      await subject.remove(rule.id);

      expect(await subject.rules(), isEmpty);
    });
  });

  group('running on import', () {
    test('no rules leaves the document alone', () async {
      final doc = await imported();

      expect((await subject.runOnImport(doc)).id, doc.id);
      expect(compression.analysed, 0);
    });

    test('a non-matching rule does not run', () async {
      await subject.add(
        action: AutomationAction.compress,
        nameContains: 'receipt',
      );

      await subject.runOnImport(await imported(name: 'Invoice.pdf'));

      expect(compression.analysed, 0);
    });

    test('a disabled rule does not run', () async {
      final rule = await subject.add(action: AutomationAction.compress);
      await subject.setEnabled(rule.id, enabled: false);

      await subject.runOnImport(await imported());

      expect(compression.analysed, 0);
    });

    // The whole point of the in-place design: one import must not leave two
    // library entries per rule.
    test('a lossless rule keeps the library at one entry', () async {
      await subject.add(action: AutomationAction.compress);
      final doc = await imported();
      final before = (await library.all()).length;

      final result = await subject.runOnImport(doc);

      expect((await library.all()).length, before);
      expect(result.id, doc.id, reason: 'the original row is kept');
    });

    test('the original row now holds the new content', () async {
      await subject.add(action: AutomationAction.compress);
      final doc = await imported();

      final result = await subject.runOnImport(doc);
      final bytes = await File(
        await library.resolveReadablePath(result),
      ).readAsBytes();

      expect(String.fromCharCodes(bytes), contains('COMPRESSED'));
    });

    // A watermark changes the page, so replacing would destroy the unmarked
    // version. It gets a new document, and the library grows by one.
    test('a watermark rule produces a second document', () async {
      await subject.add(
        action: AutomationAction.watermark,
        watermarkText: 'DRAFT',
      );
      final doc = await imported();
      final before = (await library.all()).length;

      final result = await subject.runOnImport(doc);

      expect((await library.all()).length, before + 1);
      expect(result.id, isNot(doc.id));
      expect(watermark.marks, ['DRAFT']);
    });

    test('a watermark rule with no text never runs', () async {
      await subject.add(action: AutomationAction.watermark);

      await subject.runOnImport(await imported());

      expect(
        watermark.marks,
        isEmpty,
        reason: 'it would throw on a document nobody asked about',
      );
    });

    // A document opened in place points at the USER'S OWN FILE on disk.
    // Rewriting it would modify a file outside Folio's library, which nothing
    // in this project does - so it gets a new document instead, even though
    // the action is lossless.
    test('a document opened in place is never rewritten', () async {
      await subject.add(action: AutomationAction.compress);

      final source = await Directory.systemTemp.createTemp('external');
      final external = File('${source.path}/OnDisk.pdf')
        ..writeAsBytesSync(smallPdf('USER-OWN-FILE'));
      mockResolvedPath = external.path;

      final doc = await library.openInPlace(
        external.path,
        displayName: 'OnDisk.pdf',
      );

      final result = await subject.runOnImport(doc);

      expect(result.id, isNot(doc.id), reason: 'a new document was made');
      expect(
        String.fromCharCodes(external.readAsBytesSync()),
        contains('USER-OWN-FILE'),
        reason: "the user's own file must be byte-for-byte untouched",
      );
    });

    // Automation runs unattended. An import must not fail because a rule did.
    test('a failing rule leaves the document intact', () async {
      ocr = FakeOcr(library, fails: true);
      subject = AutomationRepositoryImpl(
        dao: dao,
        library: library,
        compression: compression,
        ocr: ocr,
        watermark: watermark,
      );
      await subject.add(action: AutomationAction.ocr);
      final doc = await imported();

      final result = await subject.runOnImport(doc);

      expect(result.id, doc.id);
      expect(ocr.calls, 1, reason: 'it was attempted');
    });

    test('a failing rule does not stop the next one', () async {
      ocr = FakeOcr(library, fails: true);
      subject = AutomationRepositoryImpl(
        dao: dao,
        library: library,
        compression: compression,
        ocr: ocr,
        watermark: watermark,
      );
      await subject.add(action: AutomationAction.ocr);
      await subject.add(
        action: AutomationAction.watermark,
        watermarkText: 'DRAFT',
      );

      await subject.runOnImport(await imported());

      expect(watermark.marks, ['DRAFT']);
    });
  });
}
