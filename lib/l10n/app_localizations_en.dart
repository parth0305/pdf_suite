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

  @override
  String get emptyLibraryTitle => 'No documents yet';

  @override
  String get emptyLibraryBody =>
      'Import a PDF to get started. Files are copied into the app so they always reopen.';

  @override
  String get importAction => 'Import PDF';

  @override
  String get favoriteAction => 'Favorite';

  @override
  String get unfavoriteAction => 'Remove from favorites';

  @override
  String get renameAction => 'Rename';

  @override
  String get deleteAction => 'Delete';

  @override
  String get duplicateAction => 'Duplicate';

  @override
  String get recentsTitle => 'Recent';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get allDocumentsTitle => 'All';

  @override
  String get searchHint => 'Search documents';

  @override
  String get sortLabel => 'Sort';

  @override
  String get sortByName => 'Name';

  @override
  String get sortByDateAdded => 'Date added';

  @override
  String get sortByDateOpened => 'Last opened';

  @override
  String get sortBySize => 'Size';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get importedCopyBadge => 'Imported copy';

  @override
  String get noSearchResults => 'No documents match your search.';

  @override
  String get noRecents => 'Documents you open will appear here.';

  @override
  String get noFavorites => 'Star a document to keep it here.';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get saveAction => 'Save';

  @override
  String pageCountLabel(int count) {
    return '$count pages';
  }

  @override
  String get moreActionsLabel => 'More actions';

  @override
  String get passwordPromptTitle => 'Password required';

  @override
  String get passwordPromptHint => 'Password';

  @override
  String get passwordPromptOpen => 'Open';

  @override
  String viewerPageIndicator(int current, int total) {
    return '$current of $total';
  }

  @override
  String get viewerZoomIn => 'Zoom in';

  @override
  String get viewerZoomOut => 'Zoom out';

  @override
  String get viewerFullScreen => 'Full screen';

  @override
  String get viewerExitFullScreen => 'Exit full screen';

  @override
  String get viewerThumbnails => 'Page thumbnails';

  @override
  String get viewerOutline => 'Bookmarks';

  @override
  String get viewerNoOutline => 'This document has no bookmarks.';

  @override
  String get viewerSearch => 'Search in document';

  @override
  String get viewerNoMatches => 'No matches';

  @override
  String viewerMatchIndicator(int current, int total) {
    return '$current of $total';
  }

  @override
  String get viewerNextMatch => 'Next match';

  @override
  String get viewerPreviousMatch => 'Previous match';

  @override
  String get viewerCloseSearch => 'Close search';

  @override
  String viewerPageLabel(int number) {
    return 'Page $number';
  }
}
