import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/data/sharing/platform_export.dart';
import 'package:folio/domain/repositories/export_repository.dart';

/// Overridden at app start; reading either unoverridden is a programming error.
final exportRepositoryProvider = Provider<ExportRepository>(
  (ref) =>
      throw UnimplementedError('exportRepositoryProvider must be overridden'),
);

final platformExportProvider = Provider<PlatformExport>(
  (ref) =>
      throw UnimplementedError('platformExportProvider must be overridden'),
);
