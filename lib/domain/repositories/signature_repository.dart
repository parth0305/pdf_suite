import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/saved_signature.dart';

abstract interface class SignatureRepository {
  Future<List<SavedSignature>> all();

  Future<SavedSignature> add({
    required String label,
    required List<List<PdfPoint>> strokes,
    required double aspectRatio,
  });

  /// Stores a photographed signature: RGBA with the paper already made
  /// transparent, not the original photograph.
  ///
  /// The photograph itself is deliberately not kept. It is a picture of a
  /// person's signature on their desk, and Folio needs the extracted ink, not
  /// the room behind it.
  Future<SavedSignature> addPhoto({
    required String label,
    required List<int> rgba,
    required int pixelWidth,
    required int pixelHeight,
  });

  Future<void> rename(int id, String label);

  Future<void> delete(int id);
}
