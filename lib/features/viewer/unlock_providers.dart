import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/unlock_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final unlockRepositoryProvider = Provider<UnlockRepository>(
  (ref) =>
      throw UnimplementedError('unlockRepositoryProvider must be overridden'),
);
