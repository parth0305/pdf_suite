import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/engine/pdf_types.dart';
import 'package:folio/domain/flatten/annotation_appearance.dart';

void main() {
  group('flattenDecisionFor', () {
    test('an annotation with an appearance is painted', () {
      expect(
        flattenDecisionFor(
          '<< /Subtype /Square /AP << /N 5 0 R >> >>',
          appearance: 5,
        ),
        FlattenDecision.draw,
      );
    });

    // Removing an annotation whose value lives only in the annotation is not
    // flattening, it is deletion.
    test('an annotation with no appearance but a value is kept', () {
      expect(
        flattenDecisionFor(
          '<< /Subtype /Widget /FT /Tx /V (Priya) >>',
          appearance: null,
        ),
        FlattenDecision.keep,
      );
    });

    // Nothing to draw and nothing to lose. Keeping it leaves a document a
    // form on account of fields nobody filled in.
    test('an empty annotation with no appearance is dropped', () {
      expect(
        flattenDecisionFor(
          '<< /Subtype /Widget /FT /Tx /T (name) >>',
          appearance: null,
        ),
        FlattenDecision.drop,
      );
    });

    test('a link is kept even though it has an appearance', () {
      expect(
        flattenDecisionFor(
          '<< /Subtype /Link /AP << /N 5 0 R >> >>',
          appearance: 5,
        ),
        FlattenDecision.keep,
      );
    });

    // A popup is the note's open window. Painting it stamps a floating text
    // box onto the page.
    test('a popup is dropped, not painted', () {
      expect(
        flattenDecisionFor(
          '<< /Subtype /Popup /AP << /N 5 0 R >> >>',
          appearance: 5,
        ),
        FlattenDecision.drop,
      );
    });

    test('a hidden annotation is dropped', () {
      expect(
        flattenDecisionFor(
          '<< /Subtype /Square /F 2 /AP << /N 5 0 R >> >>',
          appearance: 5,
        ),
        FlattenDecision.drop,
      );
    });

    test('a no-view annotation is dropped', () {
      expect(
        flattenDecisionFor(
          '<< /Subtype /Square /F 32 /AP << /N 5 0 R >> >>',
          appearance: 5,
        ),
        FlattenDecision.drop,
      );
    });

    test('a printable annotation with other flags is still painted', () {
      expect(
        flattenDecisionFor(
          '<< /Subtype /Square /F 4 /AP << /N 5 0 R >> >>',
          appearance: 5,
        ),
        FlattenDecision.draw,
      );
    });
  });

  group('normalAppearanceOf', () {
    test('reads a direct reference', () {
      expect(normalAppearanceOf('<< /AP << /N 7 0 R >> >>'), 7);
    });

    // A checkbox's /N holds every state it can be in; /AS says which one it
    // is. Taking the first would paint an unticked box as ticked.
    test('picks the state named by /AS', () {
      expect(
        normalAppearanceOf(
          '<< /AS /Yes /AP << /N << /Off 8 0 R /Yes 9 0 R >> >> >>',
        ),
        9,
      );
    });

    test('a state dictionary with no /AS has no appearance', () {
      expect(
        normalAppearanceOf('<< /AP << /N << /Off 8 0 R /Yes 9 0 R >> >> >>'),
        isNull,
      );
    });

    test('no /AP at all has no appearance', () {
      expect(normalAppearanceOf('<< /Subtype /Square >>'), isNull);
    });
  });

  group('appearanceTransform', () {
    test('fits the appearance box onto the rectangle', () {
      final m = appearanceTransform(
        rect: const TextRect(left: 100, bottom: 200, right: 200, top: 400),
        bbox: const TextRect(left: 0, bottom: 0, right: 50, top: 50),
      );

      expect(m[0], 2); // 100 wide over a 50-wide box
      expect(m[3], 4); // 200 tall over a 50-tall box
      expect(m[4], 100);
      expect(m[5], 200);
    });

    test('a box that does not start at the origin is translated', () {
      final m = appearanceTransform(
        rect: const TextRect(left: 0, bottom: 0, right: 10, top: 10),
        bbox: const TextRect(left: 5, bottom: 5, right: 15, top: 15),
      );

      expect(m[0], 1);
      expect(m[4], -5);
      expect(m[5], -5);
    });

    // ISO 32000-1 §12.5.5: /BBox is transformed by /Matrix first, and the
    // bounding box of THAT is what gets fitted. A quarter-turn appearance is
    // otherwise placed at the wrong scale.
    test('a rotating matrix changes the fit', () {
      final m = appearanceTransform(
        rect: const TextRect(left: 0, bottom: 0, right: 100, top: 50),
        bbox: const TextRect(left: 0, bottom: 0, right: 50, top: 100),
        matrix: const [0, 1, -1, 0, 0, 0],
      );

      // Turned, the box is 100 wide and 50 tall - the rect exactly.
      expect(m[0], 1);
      expect(m[3], 1);
      // Its left edge moved to -100, so it has to come back.
      expect(m[4], 100);
    });

    test('a degenerate appearance box scales by one, not by infinity', () {
      final m = appearanceTransform(
        rect: const TextRect(left: 0, bottom: 0, right: 10, top: 10),
        bbox: const TextRect(left: 0, bottom: 0, right: 0, top: 10),
      );

      expect(m[0], 1);
      expect(m[0].isFinite, isTrue);
    });

    test('a rectangle written back to front is used the right way round', () {
      final m = appearanceTransform(
        rect: const TextRect(left: 200, bottom: 400, right: 100, top: 200),
        bbox: const TextRect(left: 0, bottom: 0, right: 50, top: 50),
      );

      expect(m[0], 2);
      expect(m[4], 100);
      expect(m[5], 200);
    });
  });

  group('flattenContentStream', () {
    test('each appearance is drawn inside its own q/Q', () {
      final stream = flattenContentStream(const [
        PlacedAppearance(resourceName: 'FlA0', transform: [1, 0, 0, 1, 0, 0]),
        PlacedAppearance(resourceName: 'FlA1', transform: [2, 0, 0, 2, 5, 5]),
      ]);

      expect(stream, contains('q 1 0 0 1 0 0 cm /FlA0 Do Q'));
      expect(stream, contains('q 2 0 0 2 5 5 cm /FlA1 Do Q'));
      expect('q '.allMatches(stream).length, 2);
      expect('Q'.allMatches(stream).length, 2);
    });
  });
}
