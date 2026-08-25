import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/domain/editing/page_slot.dart';
import 'package:folio/domain/engine/pdf_types.dart';

import '../../fakes/fake_page_editor.dart';

void main() {
  const handle = PdfDocumentHandle(id: 'h1', pageCount: 3);

  test('records the slots it was asked to materialise', () async {
    final editor = FakePageEditor();
    await editor.materialise(
      slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      sources: const {1: handle},
    );

    expect(editor.calls, hasLength(1));
    expect(editor.calls.single.single.sourcePageIndex, 0);
  });

  test('returns non-empty bytes', () async {
    final editor = FakePageEditor();
    final bytes = await editor.materialise(
      slots: const [PageSlot(sourceDocumentId: 1, sourcePageIndex: 0)],
      sources: const {1: handle},
    );
    expect(bytes, isNotEmpty);
  });

  test('an empty slot list throws EmptyDocument', () async {
    final editor = FakePageEditor();
    await expectLater(
      editor.materialise(slots: const [], sources: const {}),
      throwsA(isA<EmptyDocument>()),
    );
  });

  test('a slot referencing an absent source throws ArgumentError', () async {
    final editor = FakePageEditor();
    await expectLater(
      editor.materialise(
        slots: const [PageSlot(sourceDocumentId: 99, sourcePageIndex: 0)],
        sources: const {1: handle},
      ),
      throwsArgumentError,
    );
  });
}
