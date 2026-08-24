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

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @settingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsLabel;

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

  /// No description provided for @emptyLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get emptyLibraryTitle;

  /// No description provided for @emptyLibraryBody.
  ///
  /// In en, this message translates to:
  /// **'Import a PDF to get started. Files are copied into the app so they always reopen.'**
  String get emptyLibraryBody;

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import PDF'**
  String get importAction;

  /// No description provided for @favoriteAction.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favoriteAction;

  /// No description provided for @unfavoriteAction.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get unfavoriteAction;

  /// No description provided for @renameAction.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @duplicateAction.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateAction;

  /// No description provided for @recentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentsTitle;

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// No description provided for @allDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allDocumentsTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search documents'**
  String get searchHint;

  /// No description provided for @sortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortLabel;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortByName;

  /// No description provided for @sortByDateAdded.
  ///
  /// In en, this message translates to:
  /// **'Date added'**
  String get sortByDateAdded;

  /// No description provided for @sortByDateOpened.
  ///
  /// In en, this message translates to:
  /// **'Last opened'**
  String get sortByDateOpened;

  /// No description provided for @sortBySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sortBySize;

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @importedCopyBadge.
  ///
  /// In en, this message translates to:
  /// **'Imported copy'**
  String get importedCopyBadge;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No documents match your search.'**
  String get noSearchResults;

  /// No description provided for @noRecents.
  ///
  /// In en, this message translates to:
  /// **'Documents you open will appear here.'**
  String get noRecents;

  /// No description provided for @noFavorites.
  ///
  /// In en, this message translates to:
  /// **'Star a document to keep it here.'**
  String get noFavorites;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @pageCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} pages'**
  String pageCountLabel(int count);

  /// No description provided for @moreActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActionsLabel;

  /// No description provided for @passwordPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Password required'**
  String get passwordPromptTitle;

  /// No description provided for @passwordPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordPromptHint;

  /// No description provided for @passwordPromptOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get passwordPromptOpen;

  /// No description provided for @viewerPageIndicator.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String viewerPageIndicator(int current, int total);

  /// No description provided for @viewerZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get viewerZoomIn;

  /// No description provided for @viewerZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get viewerZoomOut;

  /// No description provided for @viewerFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get viewerFullScreen;

  /// No description provided for @viewerExitFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get viewerExitFullScreen;

  /// No description provided for @viewerThumbnails.
  ///
  /// In en, this message translates to:
  /// **'Page thumbnails'**
  String get viewerThumbnails;

  /// No description provided for @viewerOutline.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get viewerOutline;

  /// No description provided for @viewerNoOutline.
  ///
  /// In en, this message translates to:
  /// **'This document has no bookmarks.'**
  String get viewerNoOutline;

  /// No description provided for @viewerSearch.
  ///
  /// In en, this message translates to:
  /// **'Search in document'**
  String get viewerSearch;

  /// No description provided for @viewerNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get viewerNoMatches;

  /// No description provided for @viewerMatchIndicator.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String viewerMatchIndicator(int current, int total);

  /// No description provided for @viewerNextMatch.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get viewerNextMatch;

  /// No description provided for @viewerPreviousMatch.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get viewerPreviousMatch;

  /// No description provided for @viewerCloseSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get viewerCloseSearch;

  /// No description provided for @viewerPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String viewerPageLabel(int number);
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
