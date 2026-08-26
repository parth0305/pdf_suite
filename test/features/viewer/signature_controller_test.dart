import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/features/viewer/signature_providers.dart';

const one = SavedSignature(
  id: 1,
  label: 'Full',
  strokes: [
    [PdfPoint(0, 0), PdfPoint(1, 1)],
  ],
  aspectRatio: 2,
);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  SigningController c() => container.read(signingProvider.notifier);
  SigningState s() => container.read(signingProvider);

  test('starts with nothing chosen', () {
    expect(s().chosen, isNull);
  });

  test('choosing a signature records it', () {
    c().select(one);
    expect(s().chosen?.label, 'Full');
  });

  test('choosing null clears it', () {
    c()
      ..select(one)
      ..select(null);

    expect(s().chosen, isNull);
  });
}
