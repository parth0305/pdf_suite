import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/features/viewer/widgets/outline_panel.dart';

void main() {
  group('flattenOutline', () {
    test('flattens nested nodes depth-first with depth recorded', () {
      const nodes = [
        OutlineNode(
          title: 'Chapter 1',
          pageIndex: 0,
          children: [
            OutlineNode(title: 'Section 1.1', pageIndex: 2, children: []),
            OutlineNode(title: 'Section 1.2', pageIndex: 4, children: []),
          ],
        ),
        OutlineNode(title: 'Chapter 2', pageIndex: 10, children: []),
      ];

      final flat = flattenOutline(nodes);

      expect(flat.map((e) => e.title), [
        'Chapter 1',
        'Section 1.1',
        'Section 1.2',
        'Chapter 2',
      ]);
      expect(flat.map((e) => e.depth), [0, 1, 1, 0]);
    });

    test('preserves nodes with no destination', () {
      const nodes = [
        OutlineNode(title: 'Unlinked', pageIndex: null, children: []),
      ];
      expect(flattenOutline(nodes).single.pageIndex, isNull);
    });

    test('an empty outline flattens to an empty list', () {
      expect(flattenOutline(const []), isEmpty);
    });

    test('deeply nested nodes keep increasing depth', () {
      const nodes = [
        OutlineNode(
          title: 'A',
          pageIndex: 0,
          children: [
            OutlineNode(
              title: 'B',
              pageIndex: 1,
              children: [OutlineNode(title: 'C', pageIndex: 2, children: [])],
            ),
          ],
        ),
      ];
      expect(flattenOutline(nodes).map((e) => e.depth), [0, 1, 2]);
    });
  });
}
