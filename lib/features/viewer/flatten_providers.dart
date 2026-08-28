import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/flatten_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final flattenRepositoryProvider = Provider<FlattenRepository>(
  (ref) =>
      throw UnimplementedError('flattenRepositoryProvider must be overridden'),
);
