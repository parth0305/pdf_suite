import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/repositories/batch_repository_impl.dart';
import 'package:folio/domain/batch/batch_outcome.dart';
import 'package:folio/domain/compression/compression_estimate.dart';
import 'package:folio/domain/models/document_ref.dart';
import 'package:folio/domain/models/library_document.dart';
import 'package:folio/domain/models/protect_request.dart';
import 'package:folio/domain/repositories/compression_repository.dart';
import 'package:folio/domain/repositories/ocr_repository.dart';
import 'package:folio/domain/repositories/protection_repository.dart';
import 'package:folio/domain/repositories/watermark_repository.dart';
import 'package:folio/domain/watermark/watermark.dart';
import 'dart:typed_data';

LibraryDocument doc(int id, String name) => LibraryDocument(
  id: id,
  ref: const ManagedRef(relativePath: 'a/b.pdf', contentHash: 'h'),
  displayName: name,
  sizeBytes: 100,
  addedAt: DateTime(2026),
  isFavorite: false,
);

class FakeCompression implements CompressionRepository {
  FakeCompression({this.worthIds = const {}, this.throwIds = const {}});

  final Set<int> worthIds;
  final Set<int> throwIds;
  final saved = <int>[];

  @override
  Future<CompressionResult> analyse(int documentId) async {
    if (throwIds.contains(documentId)) throw StateError('broken');

    final worth = worthIds.contains(documentId);
    return CompressionResult(
      bytes: Uint8List(worth ? 500 : 999),
      originalBytes: 1000,
      duplicateBytes: 0,
      orphanedBytes: 0,
      deflatableBytes: 0,
    );
  }

  @override
  Future<LibraryDocument> save(int documentId, CompressionResult result) async {
    saved.add(documentId);
    return doc(documentId + 100, 'Doc $documentId (edited).pdf');
  }
}

class FakeOcr implements OcrRepository {
  FakeOcr({this.emptyIds = const {}});

  final Set<int> emptyIds;
  final seen = <int>[];

  @override
  Future<LibraryDocument> recognise(int documentId) async {
    seen.add(documentId);
    if (emptyIds.contains(documentId)) {
      throw ArgumentError.value(documentId, 'layers', 'no text to add');
    }
    return doc(documentId + 100, 'Doc $documentId (edited).pdf');
  }
}

class FakeWatermark implements WatermarkRepository {
  @override
  Future<LibraryDocument> remove(int documentId) =>
      throw UnimplementedError('removal is not exercised here');

  final marks = <int, Watermark>{};

  @override
  Future<LibraryDocument> apply(int documentId, Watermark mark) async {
    marks[documentId] = mark;
    return doc(documentId + 100, 'Doc $documentId (edited).pdf');
  }
}

class FakeProtection implements ProtectionRepository {
  final requests = <int, ProtectRequest>{};

  @override
  Future<LibraryDocument> protect(
    int documentId,
    ProtectRequest request,
  ) async {
    requests[documentId] = request;
    return doc(documentId + 100, 'Doc $documentId (edited).pdf');
  }
}

void main() {
  late FakeCompression compression;
  late FakeOcr ocr;
  late FakeWatermark watermark;
  late FakeProtection protection;
  late BatchRepositoryImpl subject;

  BatchRepositoryImpl build() => BatchRepositoryImpl(
    compression: compression,
    ocr: ocr,
    watermark: watermark,
    protection: protection,
  );

  setUp(() {
    compression = FakeCompression(worthIds: {1, 2, 3});
    ocr = FakeOcr();
    watermark = FakeWatermark();
    protection = FakeProtection();
    subject = build();
  });

  group('running to completion', () {
    // A batch that aborts on the first error leaves the user with some
    // documents processed and no record of which.
    test('one failure does not abandon the rest', () async {
      compression = FakeCompression(worthIds: {1, 2, 3}, throwIds: {2});
      subject = build();

      final outcome = await subject.run(
        action: BatchAction.compress,
        documentIds: [1, 2, 3],
      );

      expect(outcome.items, hasLength(3));
      expect(outcome.succeeded, 2);
      expect(outcome.countOf(BatchSkipReason.failed), 1);
      expect(compression.saved, [1, 3]);
    });

    test('the failure records a type, never a message', () async {
      compression = FakeCompression(worthIds: {1}, throwIds: {1});
      subject = build();

      final outcome = await subject.run(
        action: BatchAction.compress,
        documentIds: [1],
      );

      expect(outcome.items.single.detail, 'StateError');
      expect(
        outcome.items.single.detail,
        isNot(contains('broken')),
        reason: 'a message could carry a filename or a password',
      );
    });

    test('every document is reported, in order', () async {
      final outcome = await subject.run(
        action: BatchAction.compress,
        documentIds: [3, 1, 2],
      );

      expect(outcome.items.map((i) => i.documentId), [3, 1, 2]);
    });
  });

  group('skipped is not failed', () {
    // A scan gives back nothing. Ten of them would otherwise produce ten
    // near-identical copies.
    test('compression that would gain nothing is skipped', () async {
      compression = FakeCompression(worthIds: {1});
      subject = build();

      final outcome = await subject.run(
        action: BatchAction.compress,
        documentIds: [1, 2, 3],
      );

      expect(outcome.succeeded, 1);
      expect(outcome.countOf(BatchSkipReason.nothingToDo), 2);
      expect(
        outcome.countOf(BatchSkipReason.failed),
        0,
        reason: 'nothing failed - two documents simply had nothing to gain',
      );
      expect(compression.saved, [1], reason: 'no pointless copies were made');
    });

    test('OCR that recognises nothing is skipped, not failed', () async {
      ocr = FakeOcr(emptyIds: {2});
      subject = build();

      final outcome = await subject.run(
        action: BatchAction.ocr,
        documentIds: [1, 2],
      );

      expect(outcome.succeeded, 1);
      expect(outcome.countOf(BatchSkipReason.nothingToDo), 1);
      expect(outcome.countOf(BatchSkipReason.failed), 0);
    });
  });

  group('progress and cancellation', () {
    test('progress is reported after each document', () async {
      final seen = <(int, int)>[];

      await subject.run(
        action: BatchAction.compress,
        documentIds: [1, 2, 3],
        onProgress: (done, total) => seen.add((done, total)),
      );

      expect(seen, [(1, 3), (2, 3), (3, 3)]);
    });

    // Cancelling must not undo what already finished: that would be a rollback
    // nobody asked for, and the documents are already in the library.
    test('cancelling keeps what was already produced', () async {
      var calls = 0;

      final outcome = await subject.run(
        action: BatchAction.compress,
        documentIds: [1, 2, 3],
        shouldContinue: () => calls++ < 2,
      );

      expect(outcome.items, hasLength(2));
      expect(outcome.succeeded, 2);
      expect(compression.saved, [1, 2]);
    });

    test('cancelling before the first document does nothing at all', () async {
      final outcome = await subject.run(
        action: BatchAction.compress,
        documentIds: [1, 2, 3],
        shouldContinue: () => false,
      );

      expect(outcome.items, isEmpty);
      expect(outcome.producedNothing, isTrue);
      expect(compression.saved, isEmpty);
    });
  });

  group('delegation', () {
    test('watermark passes the mark through to every document', () async {
      const mark = Watermark(text: 'DRAFT');

      await subject.run(
        action: BatchAction.watermark,
        documentIds: [1, 2],
        watermark: mark,
      );

      expect(watermark.marks.keys, [1, 2]);
      expect(watermark.marks[1]!.text, 'DRAFT');
    });

    test('protect passes the password through to every document', () async {
      await subject.run(
        action: BatchAction.protect,
        documentIds: [1, 2],
        password: 'secret',
      );

      expect(protection.requests.keys, [1, 2]);
      expect(protection.requests[2]!.userPassword, 'secret');
    });
  });

  group('summarising', () {
    test('everythingWorked only when nothing was skipped', () async {
      expect(
        (await subject.run(
          action: BatchAction.compress,
          documentIds: [1, 2],
        )).everythingWorked,
        isTrue,
      );

      compression = FakeCompression(worthIds: {1});
      subject = build();

      expect(
        (await subject.run(
          action: BatchAction.compress,
          documentIds: [1, 2],
        )).everythingWorked,
        isFalse,
      );
    });

    test('an empty batch has not "worked"', () async {
      final outcome = await subject.run(
        action: BatchAction.compress,
        documentIds: const [],
      );

      expect(outcome.everythingWorked, isFalse);
      expect(outcome.producedNothing, isTrue);
    });
  });
}
