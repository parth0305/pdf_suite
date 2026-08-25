import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/constants/breakpoints.dart';

void main() {
  group('widthClassFor', () {
    test('phone widths are compact', () {
      expect(widthClassFor(320), WidthClass.compact);
      expect(widthClassFor(599.9), WidthClass.compact);
    });

    test('tablet widths are medium', () {
      expect(widthClassFor(600), WidthClass.medium);
      expect(widthClassFor(1024), WidthClass.medium);
    });

    test('desktop widths are expanded', () {
      expect(widthClassFor(1024.1), WidthClass.expanded);
      expect(widthClassFor(1920), WidthClass.expanded);
    });

    test('boundaries are inclusive at the lower bound', () {
      expect(widthClassFor(600), WidthClass.medium);
      expect(widthClassFor(599), WidthClass.compact);
    });
  });
}
