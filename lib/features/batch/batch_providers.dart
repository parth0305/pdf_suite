import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/batch_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) =>
      throw UnimplementedError('batchRepositoryProvider must be overridden'),
);
