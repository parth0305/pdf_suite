import 'dart:convert';
import 'dart:typed_data';

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
  Future<SavedSignature> addPhoto({
    required String label,
    required List<int> rgba,
    required int pixelWidth,
    required int pixelHeight,
  }) async {
    final id = await _dao.insert(
      label: label,
      // No strokes: an empty list rather than null, so `_decode` never sees a
      // shape it was not written for.
      strokes: '[]',
      aspectRatio: pixelWidth / pixelHeight,
      kind: SignatureKind.photo.name,
      imageBytes: Uint8List.fromList([
        // The dimensions travel WITH the pixels. A blob whose width is stored
        // elsewhere is one migration away from being unreadable.
        pixelWidth >> 8, pixelWidth & 0xFF,
        pixelHeight >> 8, pixelHeight & 0xFF,
        ...rgba,
      ]),
    );
    return (await all()).firstWhere((s) => s.id == id);
  }

  @override
  Future<void> rename(int id, String label) => _dao.rename(id, label);

  @override
  Future<void> delete(int id) => _dao.delete(id);

  SavedSignature _toDomain(Signature row) {
    final blob = row.imageBytes;
    final isPhoto = row.kind == SignatureKind.photo.name && blob != null;

    return SavedSignature(
      id: row.id,
      label: row.label,
      strokes: _decode(row.strokes),
      aspectRatio: row.aspectRatio,
      // An unknown kind reads as drawn. A row written by a newer build must
      // not make the signature list fail to load.
      kind: isPhoto ? SignatureKind.photo : SignatureKind.drawn,
      imageRgba: isPhoto ? blob.sublist(4) : null,
      pixelWidth: isPhoto ? (blob[0] << 8) | blob[1] : null,
      pixelHeight: isPhoto ? (blob[2] << 8) | blob[3] : null,
    );
  }

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
