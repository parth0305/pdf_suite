import 'package:folio/core/errors/app_failure.dart';
import 'package:folio/l10n/app_localizations.dart';

/// A user-facing description of a failure: a short title and a plain-language body.
///
/// Never includes [AppFailure.technicalDetail] - that goes to the log only.
class FailureMessage {
  const FailureMessage(this.title, this.body);
  final String title;
  final String body;
}

FailureMessage failureMessage(AppFailure failure, AppLocalizations l10n) {
  return switch (failure) {
    DocumentCorrupt() => FailureMessage(
      l10n.errorDocumentCorruptTitle,
      l10n.errorDocumentCorruptBody,
    ),
    DocumentMoved() => FailureMessage(
      l10n.errorDocumentMovedTitle,
      l10n.errorDocumentMovedBody,
    ),
    PermissionRevoked() => FailureMessage(
      l10n.errorPermissionRevokedTitle,
      l10n.errorPermissionRevokedBody,
    ),
    PasswordRequired() => FailureMessage(
      l10n.errorPasswordRequiredTitle,
      l10n.errorPasswordRequiredBody,
    ),
    WrongPassword() => FailureMessage(
      l10n.errorWrongPasswordTitle,
      l10n.errorWrongPasswordBody,
    ),
    UnsupportedFeature() => FailureMessage(
      l10n.errorUnsupportedFeatureTitle,
      l10n.errorUnsupportedFeatureBody,
    ),
    StorageFull() => FailureMessage(
      l10n.errorStorageFullTitle,
      l10n.errorStorageFullBody,
    ),
    EmptyDocument() => FailureMessage(
      l10n.errorEmptyDocumentTitle,
      l10n.errorEmptyDocumentBody,
    ),
    InvalidPageRange() => FailureMessage(
      l10n.errorInvalidPageRangeTitle,
      l10n.errorInvalidPageRangeBody,
    ),
    UnsupportedPdfStructure() => FailureMessage(
      l10n.errorUnsupportedPdfStructureTitle,
      l10n.errorUnsupportedPdfStructureBody,
    ),
    UnknownFailure() => FailureMessage(
      l10n.errorUnknownTitle,
      l10n.errorUnknownBody,
    ),
  };
}
