import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/metadata_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final metadataRepositoryProvider = Provider<MetadataRepository>(
  (ref) =>
      throw UnimplementedError('metadataRepositoryProvider must be overridden'),
);
