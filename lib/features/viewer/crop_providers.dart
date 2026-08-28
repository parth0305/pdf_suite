import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/crop_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final cropRepositoryProvider = Provider<CropRepository>(
  (ref) =>
      throw UnimplementedError('cropRepositoryProvider must be overridden'),
);
