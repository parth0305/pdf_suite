import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/signature_dao.dart';
import 'package:folio/data/repositories/signature_repository_impl.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/saved_signature.dart';

void main() {
  late AppDatabase db;
  late SignatureRepositoryImpl subject;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    subject = SignatureRepositoryImpl(dao: SignatureDao(db));
  });

  tearDown(() => db.close());

  /// 3x2 RGBA, distinguishable per pixel.
  final rgba = <int>[
    for (var i = 0; i < 6; i++) ...[i * 10, i * 10 + 1, i * 10 + 2, 255 - i],
  ];

  group('storing a photographed signature', () {
    test('it round-trips with its pixels and dimensions', () async {
      await subject.addPhoto(
        label: 'Mine',
        rgba: rgba,
        pixelWidth: 3,
        pixelHeight: 2,
      );

      final saved = (await subject.all()).single;

      expect(saved.kind, SignatureKind.photo);
      expect(saved.pixelWidth, 3);
      expect(saved.pixelHeight, 2);
      expect(saved.imageRgba, rgba);
    });

    // Width and height are stored inside the blob rather than in columns of
    // their own: a blob whose dimensions live elsewhere is one migration away
    // from being unreadable.
    test('dimensions larger than a byte survive', () async {
      await subject.addPhoto(
        label: 'Big',
        rgba: List<int>.filled(2000 * 4, 7),
        pixelWidth: 1000,
        pixelHeight: 2,
      );

      final saved = (await subject.all()).single;

      expect(saved.pixelWidth, 1000);
      expect(saved.pixelHeight, 2);
    });

    test('the aspect ratio comes from the pixels', () async {
      await subject.addPhoto(
        label: 'Wide',
        rgba: List<int>.filled(200 * 4, 0),
        pixelWidth: 100,
        pixelHeight: 2,
      );

      expect((await subject.all()).single.aspectRatio, 50);
    });

    test('it is placeable', () async {
      await subject.addPhoto(
        label: 'Mine',
        rgba: rgba,
        pixelWidth: 3,
        pixelHeight: 2,
      );

      expect((await subject.all()).single.isPlaceable, isTrue);
    });
  });

  group('the two kinds stay distinct', () {
    test('a drawn signature is unaffected', () async {
      await subject.add(
        label: 'Drawn',
        strokes: [
          [const PdfPoint(0, 0), const PdfPoint(1, 1)],
        ],
        aspectRatio: 2,
      );

      final saved = (await subject.all()).single;

      expect(saved.kind, SignatureKind.drawn);
      expect(saved.imageRgba, isNull);
      expect(saved.strokes, hasLength(1));
      expect(saved.isPlaceable, isTrue);
    });

    test('both can be stored side by side', () async {
      await subject.add(
        label: 'Drawn',
        strokes: [
          [const PdfPoint(0, 0)],
        ],
        aspectRatio: 1,
      );
      await subject.addPhoto(
        label: 'Photo',
        rgba: rgba,
        pixelWidth: 3,
        pixelHeight: 2,
      );

      final all = await subject.all();

      expect(all.map((s) => s.kind), [
        SignatureKind.drawn,
        SignatureKind.photo,
      ]);
    });

    // A row that survived a failed save would otherwise be placed as nothing
    // while reporting success.
    test('a drawn signature with no strokes is not placeable', () async {
      await subject.add(label: 'Empty', strokes: const [], aspectRatio: 1);

      expect((await subject.all()).single.isPlaceable, isFalse);
    });
  });

  test('deleting removes it', () async {
    final photo = await subject.addPhoto(
      label: 'Mine',
      rgba: rgba,
      pixelWidth: 3,
      pixelHeight: 2,
    );

    await subject.delete(photo.id);

    expect(await subject.all(), isEmpty);
  });
}
