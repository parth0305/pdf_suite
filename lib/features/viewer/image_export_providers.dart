import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/image_export_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final imageExportRepositoryProvider = Provider<ImageExportRepository>(
  (ref) => throw UnimplementedError(
    'imageExportRepositoryProvider must be overridden',
  ),
);
