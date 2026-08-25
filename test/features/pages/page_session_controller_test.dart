import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/pages/providers.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    container
        .read(pageSessionProvider.notifier)
        .start(documentId: 1, pageCount: 4);
  });

  tearDown(() => container.dispose());

  PageSessionController controller() =>
      container.read(pageSessionProvider.notifier);
  PageSessionState state() => container.read(pageSessionProvider);

  group('selection', () {
    test('starts empty', () {
      expect(state().selection, isEmpty);
    });

    test('toggling adds then removes', () {
      controller().toggleSelection(2);
      expect(state().selection, {2});
      controller().toggleSelection(2);
      expect(state().selection, isEmpty);
    });

    test('select all selects every page', () {
      controller().selectAll();
      expect(state().selection, {0, 1, 2, 3});
    });

    // Stale indices after a delete would act on the wrong pages next time.
    test('deleting clears the selection', () {
      controller().toggleSelection(1);
      controller().deleteSelected();
      expect(state().selection, isEmpty);
      expect(state().session.slots, hasLength(3));
    });

    test('reordering clears the selection', () {
      controller().toggleSelection(0);
      controller().move(0, 2);
      expect(state().selection, isEmpty);
    });
  });

  group('operations', () {
    test('rotate applies to the selection only', () {
      controller().toggleSelection(0);
      controller().rotateSelected(1);
      expect(state().session.slots[0].quarterTurns, 1);
      expect(state().session.slots[1].quarterTurns, 0);
    });

    test('operations with no selection do nothing', () {
      controller().rotateSelected(1);
      expect(state().session.isDirty, isFalse);
    });

    test('deleting every page is refused', () {
      controller().selectAll();
      controller().deleteSelected();
      expect(
        state().session.slots,
        isNotEmpty,
        reason: 'a document must keep at least one page',
      );
    });

    test('duplicating adds pages', () {
      controller().toggleSelection(0);
      controller().duplicateSelected();
      expect(state().session.slots, hasLength(5));
    });

    test('undo is reflected in state', () {
      controller().toggleSelection(0);
      controller().deleteSelected();
      expect(state().session.slots, hasLength(3));

      controller().undo();
      expect(state().session.slots, hasLength(4));
    });
  });
}
