import 'dart:convert';

import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/signature_dao.dart';
import 'package:folio/domain/annotations/pdf_point.dart';
import 'package:folio/domain/models/saved_signature.dart';
import 'package:folio/domain/repositories/signature_repository.dart';

class SignatureRepositoryImpl implements SignatureRepository {
  SignatureRepositoryImpl({required SignatureDao dao}) : _dao = dao;

  final SignatureDao _dao;

  @override
  Future<List<SavedSignature>> all() async =>
      (await _dao.all()).map(_toDomain).toList();

  @override
  Future<SavedSignature> add({
    required String label,
    required List<List<PdfPoint>> strokes,
    required double aspectRatio,
  }) async {
    final id = await _dao.insert(
      label: label,
      strokes: _encode(strokes),
      aspectRatio: aspectRatio,
    );
    return (await all()).firstWhere((s) => s.id == id);
  }

  @override
  Future<void> rename(int id, String label) => _dao.rename(id, label);

  @override
  Future<void> delete(int id) => _dao.delete(id);

  SavedSignature _toDomain(Signature row) => SavedSignature(
    id: row.id,
    label: row.label,
    strokes: _decode(row.strokes),
    aspectRatio: row.aspectRatio,
  );

  /// Stroke boundaries are preserved as nesting. Flattening them here would
  /// join the strokes when the signature is placed.
  static String _encode(List<List<PdfPoint>> strokes) => jsonEncode([
    for (final stroke in strokes)
      [
        for (final p in stroke) {'x': p.x, 'y': p.y},
      ],
  ]);

  static List<List<PdfPoint>> _decode(String json) => [
    for (final stroke in jsonDecode(json) as List)
      [
        for (final p in stroke as List)
          PdfPoint(
            (p as Map<String, dynamic>)['x'] as double,
            p['y'] as double,
          ),
      ],
  ];
}
