import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/form_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final formRepositoryProvider = Provider<FormRepository>(
  (ref) =>
      throw UnimplementedError('formRepositoryProvider must be overridden'),
);
