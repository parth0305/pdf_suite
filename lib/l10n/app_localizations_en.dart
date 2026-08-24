// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Folio';

  @override
  String get libraryTitle => 'Library';

  @override
  String get settingsLabel => 'Settings';

  @override
  String get errorDocumentCorruptTitle => 'Unable to open this PDF.';

  @override
  String get errorDocumentCorruptBody =>
      'The file may be corrupted or use an unsupported PDF feature.';

  @override
  String get errorDocumentMovedTitle => 'This document has moved.';

  @override
  String get errorDocumentMovedBody =>
      'It may have been renamed, moved, or deleted outside the app.';

  @override
  String get errorPermissionRevokedTitle => 'No longer able to open this file.';

  @override
  String get errorPermissionRevokedBody =>
      'Permission to read it was withdrawn. Open it again to restore access.';

  @override
  String get errorPasswordRequiredTitle => 'This PDF is password protected.';

  @override
  String get errorPasswordRequiredBody => 'Enter the password to open it.';

  @override
  String get errorWrongPasswordTitle => 'Incorrect password.';

  @override
  String get errorWrongPasswordBody => 'Check the password and try again.';

  @override
  String get errorUnsupportedFeatureTitle => 'Unable to display this PDF.';

  @override
  String get errorUnsupportedFeatureBody =>
      'It uses a PDF feature this app does not support yet.';

  @override
  String get errorStorageFullTitle => 'Not enough storage.';

  @override
  String get errorStorageFullBody => 'Free up some space and try again.';

  @override
  String get errorUnknownTitle => 'Something went wrong.';

  @override
  String get errorUnknownBody => 'The operation could not be completed.';
}
