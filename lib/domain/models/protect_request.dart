import 'package:folio/domain/pdf/pdf_permissions.dart';

/// What the user asked for when protecting a document.
class ProtectRequest {
  const ProtectRequest({
    required this.userPassword,
    this.ownerPassword,
    this.permissions = PdfPermissions.all,
  });

  /// Opens the document, subject to [permissions].
  final String userPassword;

  /// Opens the document with full rights. Empty or null means the user
  /// password serves as both, which is the only sensible default: a
  /// restriction nobody can lift is a restriction on the author too.
  final String? ownerPassword;

  final PdfPermissions permissions;

  /// Null when the owner password is absent or the same as the user one, so
  /// the writer does not record a redundant second password.
  String? get distinctOwnerPassword {
    final owner = ownerPassword;
    if (owner == null || owner.isEmpty || owner == userPassword) return null;
    return owner;
  }
}
