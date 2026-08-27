import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/redaction/redaction_box.dart';
import 'package:folio/features/viewer/redaction_providers.dart';

RedactionBox box(int page, double left) => RedactionBox(
  pageIndex: page,
  rect: TextRect(left: left, right: left + 10, top: 20, bottom: 10),
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  RedactionSession get() => container.read(redactionSessionProvider.notifier);

  test('starts empty, so nothing is pending until the user draws', () {
    expect(container.read(redactionSessionProvider), isEmpty);
  });

  test('adds boxes in order', () {
    get()
      ..add(box(0, 0))
      ..add(box(0, 50));

    expect(container.read(redactionSessionProvider), hasLength(2));
    expect(container.read(redactionSessionProvider).last.rect.left, 50);
  });

  test('removes one box without disturbing the others', () {
    get()
      ..add(box(0, 0))
      ..add(box(0, 50))
      ..removeAt(0);

    final boxes = container.read(redactionSessionProvider);
    expect(boxes, hasLength(1));
    expect(boxes.single.rect.left, 50);
  });

  test('replaces a box in place, which is what move and resize do', () {
    get()
      ..add(box(0, 0))
      ..add(box(0, 50))
      ..replaceAt(0, box(0, 99));

    final boxes = container.read(redactionSessionProvider);
    expect(boxes.first.rect.left, 99);
    expect(boxes.last.rect.left, 50, reason: 'the other is untouched');
  });

  test('onPage filters by page', () {
    get()
      ..add(box(0, 0))
      ..add(box(1, 0))
      ..add(box(0, 50));

    expect(get().onPage(0), hasLength(2));
    expect(get().onPage(1), hasLength(1));
    expect(get().onPage(2), isEmpty);
  });

  test('clear discards everything pending', () {
    get()
      ..add(box(0, 0))
      ..clear();

    expect(container.read(redactionSessionProvider), isEmpty);
  });
}
