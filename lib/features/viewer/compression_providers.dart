import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/compression_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final compressionRepositoryProvider = Provider<CompressionRepository>(
  (ref) => throw UnimplementedError(
    'compressionRepositoryProvider must be overridden',
  ),
);
