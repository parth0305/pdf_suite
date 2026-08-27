import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/ocr_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final ocrRepositoryProvider = Provider<OcrRepository>(
  (ref) => throw UnimplementedError('ocrRepositoryProvider must be overridden'),
);
