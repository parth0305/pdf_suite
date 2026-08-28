import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/numbering_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final numberingRepositoryProvider = Provider<NumberingRepository>(
  (ref) => throw UnimplementedError(
    'numberingRepositoryProvider must be overridden',
  ),
);
