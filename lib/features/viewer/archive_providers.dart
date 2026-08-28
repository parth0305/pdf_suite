import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/archive_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) =>
      throw UnimplementedError('archiveRepositoryProvider must be overridden'),
);
