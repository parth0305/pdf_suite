import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/protection_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final protectionRepositoryProvider = Provider<ProtectionRepository>(
  (ref) => throw UnimplementedError(
    'protectionRepositoryProvider must be overridden',
  ),
);
