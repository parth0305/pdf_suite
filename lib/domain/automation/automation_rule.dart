import 'package:folio/domain/models/library_document.dart';

/// What an automation rule does when it matches.
///
/// **Protect is deliberately absent.** A rule that runs unattended needs its
/// password at rest to use it, which turns a feature whose whole value is that
/// Folio cannot recover your password into one where Folio keeps it.
enum AutomationAction { compress, ocr, watermark }

extension AutomationActionRules on AutomationAction {
  /// Whether this action changes what a page looks like.
  ///
  /// Lossless actions rewrite the library's own copy; a watermark cannot,
  /// because replacing a document with a marked version destroys the unmarked
  /// one.
  bool get isLossless => switch (this) {
    AutomationAction.compress || AutomationAction.ocr => true,
    AutomationAction.watermark => false,
  };
}

/// A rule that runs when a document enters the library.
class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.action,
    this.enabled = true,
    this.nameContains,
    this.minSizeBytes,
    this.watermarkText,
  });

  final int id;
  final AutomationAction action;
  final bool enabled;

  /// Matches when the document's name contains this, case-insensitively.
  /// Null means every name.
  final String? nameContains;

  /// Matches documents at least this large. Null means every size.
  ///
  /// The usual reason to want it: only compress things big enough to be worth
  /// compressing.
  final int? minSizeBytes;

  /// Required when [action] is watermark; ignored otherwise.
  final String? watermarkText;

  /// Whether this rule should run against [document].
  ///
  /// A disabled rule matches nothing. Conditions are ANDed, and an absent
  /// condition is not a condition rather than a condition that fails.
  bool matches(LibraryDocument document) {
    if (!enabled) return false;

    final needle = nameContains;
    if (needle != null && needle.trim().isNotEmpty) {
      if (!document.displayName.toLowerCase().contains(
        needle.trim().toLowerCase(),
      )) {
        return false;
      }
    }

    final minimum = minSizeBytes;
    if (minimum != null && document.sizeBytes < minimum) return false;

    return true;
  }

  /// A rule that cannot do its job. A watermark rule with no text would throw
  /// at run time, on a document the user did not ask about.
  bool get isRunnable =>
      action != AutomationAction.watermark ||
      (watermarkText != null && watermarkText!.trim().isNotEmpty);

  AutomationRule copyWith({
    bool? enabled,
    AutomationAction? action,
    String? nameContains,
    int? minSizeBytes,
    String? watermarkText,
  }) => AutomationRule(
    id: id,
    action: action ?? this.action,
    enabled: enabled ?? this.enabled,
    nameContains: nameContains ?? this.nameContains,
    minSizeBytes: minSizeBytes ?? this.minSizeBytes,
    watermarkText: watermarkText ?? this.watermarkText,
  );
}
