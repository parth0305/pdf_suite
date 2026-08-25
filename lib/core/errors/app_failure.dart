/// Typed application failures.
///
/// Raw exceptions never reach the UI (brief section 34). Every failure carries a
/// stable [code] for logging and an optional [technicalDetail] that is logged but
/// never displayed.
///
/// Implements [Exception] so that generic `on Exception` handlers catch these
/// too. Without it, an ordinary try/catch written against Exception would
/// silently let an AppFailure escape.
sealed class AppFailure implements Exception {
  const AppFailure({this.technicalDetail});

  final String? technicalDetail;

  String get code;
}

final class DocumentCorrupt extends AppFailure {
  const DocumentCorrupt({super.technicalDetail});
  @override
  String get code => 'document_corrupt';
}

final class DocumentMoved extends AppFailure {
  const DocumentMoved({super.technicalDetail});
  @override
  String get code => 'document_moved';
}

final class PermissionRevoked extends AppFailure {
  const PermissionRevoked({super.technicalDetail});
  @override
  String get code => 'permission_revoked';
}

final class PasswordRequired extends AppFailure {
  const PasswordRequired({super.technicalDetail});
  @override
  String get code => 'password_required';
}

final class WrongPassword extends AppFailure {
  const WrongPassword({super.technicalDetail});
  @override
  String get code => 'wrong_password';
}

final class UnsupportedFeature extends AppFailure {
  const UnsupportedFeature({super.technicalDetail});
  @override
  String get code => 'unsupported_feature';
}

final class StorageFull extends AppFailure {
  const StorageFull({super.technicalDetail});
  @override
  String get code => 'storage_full';
}

final class EmptyDocument extends AppFailure {
  const EmptyDocument({super.technicalDetail});
  @override
  String get code => 'empty_document';
}

final class InvalidPageRange extends AppFailure {
  const InvalidPageRange({super.technicalDetail});
  @override
  String get code => 'invalid_page_range';
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure({super.technicalDetail});
  @override
  String get code => 'unknown';
}
