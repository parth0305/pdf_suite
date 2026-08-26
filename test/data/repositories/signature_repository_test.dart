import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/signature_dao.dart';
import 'package:folio/data/repositories/signature_repository_impl.dart';
import 'package:folio/domain/annotations/pdf_point.dart';

void main() {
  late AppDatabase db;
  late SignatureRepositoryImpl subject;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    subject = SignatureRepositoryImpl(dao: SignatureDao(db));
  });

  tearDown(() => db.close());

  const strokes = [
    [PdfPoint(0, 0), PdfPoint(0.5, 1)],
    [PdfPoint(0.6, 0), PdfPoint(1, 1)],
  ];

  test('starts empty', () async {
    expect(await subject.all(), isEmpty);
  });

  test('adding returns the stored signature', () async {
    final s = await subject.add(
      label: 'Full',
      strokes: strokes,
      aspectRatio: 2.5,
    );

    expect(s.label, 'Full');
    expect(s.aspectRatio, 2.5);
    expect(s.strokes, hasLength(2));
  });

  // Stroke boundaries are the whole point: flattening them on the way through
  // storage would join the strokes when the signature is placed.
  test('strokes survive a storage round trip with their boundaries', () async {
    await subject.add(label: 'Full', strokes: strokes, aspectRatio: 2.5);

    final loaded = (await subject.all()).single;
    expect(loaded.strokes, hasLength(2));
    expect(loaded.strokes.first, hasLength(2));
    expect(loaded.strokes.last.first.x, closeTo(0.6, 0.0001));
    expect(loaded.strokes.first.last.y, closeTo(1, 0.0001));
  });

  test('renaming changes only the label', () async {
    final s = await subject.add(
      label: 'Full',
      strokes: strokes,
      aspectRatio: 2.5,
    );
    await subject.rename(s.id, 'Initials');

    final loaded = (await subject.all()).single;
    expect(loaded.label, 'Initials');
    expect(loaded.strokes, hasLength(2));
  });

  test('deleting removes it', () async {
    final s = await subject.add(
      label: 'Full',
      strokes: strokes,
      aspectRatio: 2.5,
    );
    await subject.delete(s.id);

    expect(await subject.all(), isEmpty);
  });

  test('several signatures coexist', () async {
    await subject.add(label: 'Full', strokes: strokes, aspectRatio: 2.5);
    await subject.add(label: 'Initials', strokes: strokes, aspectRatio: 1.2);

    expect((await subject.all()).map((s) => s.label), ['Full', 'Initials']);
  });
}
