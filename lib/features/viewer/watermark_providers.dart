import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/watermark_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final watermarkRepositoryProvider = Provider<WatermarkRepository>(
  (ref) => throw UnimplementedError(
    'watermarkRepositoryProvider must be overridden',
  ),
);
