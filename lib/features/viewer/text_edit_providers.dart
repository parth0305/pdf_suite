import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/repositories/text_edit_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final textEditRepositoryProvider = Provider<TextEditRepository>(
  (ref) =>
      throw UnimplementedError('textEditRepositoryProvider must be overridden'),
);
