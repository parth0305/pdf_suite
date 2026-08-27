import 'package:folio/domain/automation/automation_rule.dart';
import 'package:folio/domain/models/library_document.dart';

/// Stores automation rules and runs them against newly added documents.
abstract interface class AutomationRepository {
  Future<List<AutomationRule>> rules();

  Future<AutomationRule> add({
    required AutomationAction action,
    String? nameContains,
    int? minSizeBytes,
    String? watermarkText,
  });

  Future<void> setEnabled(int id, {required bool enabled});

  Future<void> remove(int id);

  /// Runs every matching rule against [document] and returns what it became.
  ///
  /// Returns the document unchanged when nothing matched. Never throws for a
  /// rule that fails: automation runs without anyone watching, and an import
  /// must not fail because a rule did.
  Future<LibraryDocument> runOnImport(LibraryDocument document);
}
