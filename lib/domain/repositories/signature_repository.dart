import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/saved_signature.dart';

abstract interface class SignatureRepository {
  Future<List<SavedSignature>> all();

  Future<SavedSignature> add({
    required String label,
    required List<List<PdfPoint>> strokes,
    required double aspectRatio,
  });

  Future<void> rename(int id, String label);

  Future<void> delete(int id);
}
