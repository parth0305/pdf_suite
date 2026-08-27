import 'package:drift/drift.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/domain/automation/automation_rule.dart';

part 'automation_dao.g.dart';

@DriftAccessor(tables: [AutomationRules])
class AutomationDao extends DatabaseAccessor<AppDatabase>
    with _$AutomationDaoMixin {
  AutomationDao(super.db);

  /// Every stored rule, oldest first, in the order they will run.
  ///
  /// A row naming an action this build does not know is **dropped**, not
  /// surfaced as an error. `protect` was considered and rejected as an
  /// automatable action; a database written by a build that allowed it must
  /// not make the automation screen fail to load.
  Future<List<AutomationRule>> all() async {
    final rows = await (select(
      automationRules,
    )..orderBy([(t) => OrderingTerm(expression: t.id)])).get();

    return [
      for (final row in rows)
        if (_actionOf(row.action) case final action?)
          AutomationRule(
            id: row.id,
            action: action,
            enabled: row.enabled,
            nameContains: row.nameContains,
            minSizeBytes: row.minSizeBytes,
            watermarkText: row.watermarkText,
          ),
    ];
  }

  Future<AutomationRule> insertRule({
    required AutomationAction action,
    String? nameContains,
    int? minSizeBytes,
    String? watermarkText,
  }) async {
    final id = await into(automationRules).insert(
      AutomationRulesCompanion.insert(
        action: action.name,
        nameContains: Value(nameContains),
        minSizeBytes: Value(minSizeBytes),
        watermarkText: Value(watermarkText),
      ),
    );

    return AutomationRule(
      id: id,
      action: action,
      nameContains: nameContains,
      minSizeBytes: minSizeBytes,
      watermarkText: watermarkText,
    );
  }

  Future<void> setEnabled(int id, {required bool enabled}) =>
      (update(automationRules)..where((t) => t.id.equals(id))).write(
        AutomationRulesCompanion(enabled: Value(enabled)),
      );

  Future<void> deleteRule(int id) =>
      (delete(automationRules)..where((t) => t.id.equals(id))).go();

  AutomationAction? _actionOf(String name) {
    for (final action in AutomationAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }
}
