import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/domain/automation/automation_rule.dart';
import 'package:folio/domain/repositories/automation_repository.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final automationRepositoryProvider = Provider<AutomationRepository>(
  (ref) => throw UnimplementedError(
    'automationRepositoryProvider must be overridden',
  ),
);

/// The stored rules, for the automation screen.
final automationRulesProvider = FutureProvider<List<AutomationRule>>(
  (ref) => ref.watch(automationRepositoryProvider).rules(),
);
