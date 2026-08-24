import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Folio'**
  String get appTitle;

  /// No description provided for @errorDocumentCorruptTitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to open this PDF.'**
  String get errorDocumentCorruptTitle;

  /// No description provided for @errorDocumentCorruptBody.
  ///
  /// In en, this message translates to:
  /// **'The file may be corrupted or use an unsupported PDF feature.'**
  String get errorDocumentCorruptBody;

  /// No description provided for @errorDocumentMovedTitle.
  ///
  /// In en, this message translates to:
  /// **'This document has moved.'**
  String get errorDocumentMovedTitle;

  /// No description provided for @errorDocumentMovedBody.
  ///
  /// In en, this message translates to:
  /// **'It may have been renamed, moved, or deleted outside the app.'**
  String get errorDocumentMovedBody;

  /// No description provided for @errorPermissionRevokedTitle.
  ///
  /// In en, this message translates to:
  /// **'No longer able to open this file.'**
  String get errorPermissionRevokedTitle;

  /// No description provided for @errorPermissionRevokedBody.
  ///
  /// In en, this message translates to:
  /// **'Permission to read it was withdrawn. Open it again to restore access.'**
  String get errorPermissionRevokedBody;

  /// No description provided for @errorPasswordRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'This PDF is password protected.'**
  String get errorPasswordRequiredTitle;

  /// No description provided for @errorPasswordRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the password to open it.'**
  String get errorPasswordRequiredBody;

  /// No description provided for @errorWrongPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password.'**
  String get errorWrongPasswordTitle;

  /// No description provided for @errorWrongPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Check the password and try again.'**
  String get errorWrongPasswordBody;

  /// No description provided for @errorUnsupportedFeatureTitle.
  ///
  /// In en, this message translates to:
  /// **'Unable to display this PDF.'**
  String get errorUnsupportedFeatureTitle;

  /// No description provided for @errorUnsupportedFeatureBody.
  ///
  /// In en, this message translates to:
  /// **'It uses a PDF feature this app does not support yet.'**
  String get errorUnsupportedFeatureBody;

  /// No description provided for @errorStorageFullTitle.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage.'**
  String get errorStorageFullTitle;

  /// No description provided for @errorStorageFullBody.
  ///
  /// In en, this message translates to:
  /// **'Free up some space and try again.'**
  String get errorStorageFullBody;

  /// No description provided for @errorUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get errorUnknownTitle;

  /// No description provided for @errorUnknownBody.
  ///
  /// In en, this message translates to:
  /// **'The operation could not be completed.'**
  String get errorUnknownBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
