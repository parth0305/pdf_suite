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

  /// No description provided for @collectionsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get collectionsAll;

  /// No description provided for @collectionNew.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get collectionNew;

  /// No description provided for @collectionNameHint.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get collectionNameHint;

  /// No description provided for @moveToAction.
  ///
  /// In en, this message translates to:
  /// **'Move to'**
  String get moveToAction;

  /// No description provided for @moveToRoot.
  ///
  /// In en, this message translates to:
  /// **'Library root'**
  String get moveToRoot;

  /// No description provided for @saveAsAction.
  ///
  /// In en, this message translates to:
  /// **'Save a copy'**
  String get saveAsAction;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Copy saved'**
  String get exportSuccess;

  /// No description provided for @deleteFolderAction.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolderAction;

  /// No description provided for @renameFolderAction.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get renameFolderAction;

  /// No description provided for @deleteFolderExplain.
  ///
  /// In en, this message translates to:
  /// **'Documents in this folder return to the library root. Nothing is deleted.'**
  String get deleteFolderExplain;

  /// No description provided for @createAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createAction;

  /// No description provided for @noDocumentsInFolder.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty.'**
  String get noDocumentsInFolder;

  /// No description provided for @errorEmptyDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to save.'**
  String get errorEmptyDocumentTitle;

  /// No description provided for @errorEmptyDocumentBody.
  ///
  /// In en, this message translates to:
  /// **'This document has no pages left. Add or restore a page before saving.'**
  String get errorEmptyDocumentBody;

  /// No description provided for @errorInvalidPageRangeTitle.
  ///
  /// In en, this message translates to:
  /// **'That page range isn\'t valid.'**
  String get errorInvalidPageRangeTitle;

  /// No description provided for @errorInvalidPageRangeBody.
  ///
  /// In en, this message translates to:
  /// **'Check the page numbers and try again.'**
  String get errorInvalidPageRangeBody;

  /// No description provided for @pagesMode.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get pagesMode;

  /// No description provided for @readMode.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get readMode;

  /// No description provided for @pagesSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String pagesSelectedCount(int count);

  /// No description provided for @pagesSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get pagesSelectAll;

  /// No description provided for @pagesClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get pagesClearSelection;

  /// No description provided for @pagesRotateLeft.
  ///
  /// In en, this message translates to:
  /// **'Rotate left'**
  String get pagesRotateLeft;

  /// No description provided for @pagesRotateRight.
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get pagesRotateRight;

  /// No description provided for @pagesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete pages'**
  String get pagesDelete;

  /// No description provided for @pagesDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate pages'**
  String get pagesDuplicate;

  /// No description provided for @pagesExtract.
  ///
  /// In en, this message translates to:
  /// **'Extract to new document'**
  String get pagesExtract;

  /// No description provided for @pagesInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert pages from…'**
  String get pagesInsert;

  /// No description provided for @pagesUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get pagesUndo;

  /// No description provided for @pagesRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get pagesRedo;

  /// No description provided for @pagesApply.
  ///
  /// In en, this message translates to:
  /// **'Save as new document'**
  String get pagesApply;

  /// No description provided for @pagesDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get pagesDiscard;

  /// No description provided for @pagesDiscardPrompt.
  ///
  /// In en, this message translates to:
  /// **'Discard your page changes? The original document is untouched either way.'**
  String get pagesDiscardPrompt;

  /// No description provided for @pagesApplied.
  ///
  /// In en, this message translates to:
  /// **'Saved as {name}'**
  String pagesApplied(String name);

  /// No description provided for @pagesSplit.
  ///
  /// In en, this message translates to:
  /// **'Split document'**
  String get pagesSplit;

  /// No description provided for @splitEveryPage.
  ///
  /// In en, this message translates to:
  /// **'Every page becomes its own document'**
  String get splitEveryPage;

  /// No description provided for @splitByRanges.
  ///
  /// In en, this message translates to:
  /// **'Custom ranges'**
  String get splitByRanges;

  /// No description provided for @splitRangeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1-3, 7, 10-12'**
  String get splitRangeHint;

  /// No description provided for @splitOutputCount.
  ///
  /// In en, this message translates to:
  /// **'{count} documents will be created'**
  String splitOutputCount(int count);

  /// No description provided for @splitConfirm.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get splitConfirm;

  /// No description provided for @librarySelectMode.
  ///
  /// In en, this message translates to:
  /// **'Select documents'**
  String get librarySelectMode;

  /// No description provided for @libraryMergeSelected.
  ///
  /// In en, this message translates to:
  /// **'Merge selected'**
  String get libraryMergeSelected;

  /// No description provided for @libraryExitSelect.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get libraryExitSelect;

  /// No description provided for @mergeNeedsTwo.
  ///
  /// In en, this message translates to:
  /// **'Select at least two documents to merge.'**
  String get mergeNeedsTwo;

  /// No description provided for @insertChooseDocument.
  ///
  /// In en, this message translates to:
  /// **'Choose a document to insert'**
  String get insertChooseDocument;

  /// No description provided for @insertNoOtherDocuments.
  ///
  /// In en, this message translates to:
  /// **'There are no other documents to insert.'**
  String get insertNoOtherDocuments;

  /// No description provided for @errorUnsupportedPdfStructureTitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t add markup to this PDF.'**
  String get errorUnsupportedPdfStructureTitle;

  /// No description provided for @errorUnsupportedPdfStructureBody.
  ///
  /// In en, this message translates to:
  /// **'It uses a newer PDF structure this app can\'t safely modify yet. The document is unchanged.'**
  String get errorUnsupportedPdfStructureBody;

  /// No description provided for @markupMode.
  ///
  /// In en, this message translates to:
  /// **'Markup'**
  String get markupMode;

  /// No description provided for @markupHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get markupHighlight;

  /// No description provided for @markupUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get markupUnderline;

  /// No description provided for @markupStrikeOut.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get markupStrikeOut;

  /// No description provided for @markupUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo markup'**
  String get markupUndo;

  /// No description provided for @markupSave.
  ///
  /// In en, this message translates to:
  /// **'Save with markup'**
  String get markupSave;

  /// No description provided for @markupCount.
  ///
  /// In en, this message translates to:
  /// **'{count} marked'**
  String markupCount(int count);

  /// No description provided for @markupSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved as {name}'**
  String markupSaved(String name);

  /// No description provided for @markupSelectFirst.
  ///
  /// In en, this message translates to:
  /// **'Select some text to mark it up.'**
  String get markupSelectFirst;

  /// No description provided for @markupDiscardPrompt.
  ///
  /// In en, this message translates to:
  /// **'Discard your markup? The original document is untouched either way.'**
  String get markupDiscardPrompt;

  /// No description provided for @drawMode.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get drawMode;

  /// No description provided for @drawPen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get drawPen;

  /// No description provided for @drawRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get drawRectangle;

  /// No description provided for @drawOval.
  ///
  /// In en, this message translates to:
  /// **'Oval'**
  String get drawOval;

  /// No description provided for @drawLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get drawLine;

  /// No description provided for @drawArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get drawArrow;

  /// No description provided for @drawColour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get drawColour;

  /// No description provided for @drawThickness.
  ///
  /// In en, this message translates to:
  /// **'Thickness'**
  String get drawThickness;

  /// No description provided for @drawUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get drawUndo;

  /// No description provided for @drawSave.
  ///
  /// In en, this message translates to:
  /// **'Save with drawings'**
  String get drawSave;

  /// No description provided for @drawDiscardPrompt.
  ///
  /// In en, this message translates to:
  /// **'Discard your drawings? The original document is untouched either way.'**
  String get drawDiscardPrompt;

  /// No description provided for @annotateMode.
  ///
  /// In en, this message translates to:
  /// **'Annotate'**
  String get annotateMode;

  /// No description provided for @annotationsMode.
  ///
  /// In en, this message translates to:
  /// **'Edit annotations'**
  String get annotationsMode;

  /// No description provided for @annotationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This page has no annotations.'**
  String get annotationsEmpty;

  /// No description provided for @annotationsDeleteOnly.
  ///
  /// In en, this message translates to:
  /// **'Delete only'**
  String get annotationsDeleteOnly;

  /// No description provided for @annotationsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get annotationsDelete;

  /// No description provided for @annotationsUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get annotationsUndo;

  /// No description provided for @annotationsSave.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get annotationsSave;

  /// No description provided for @annotationsSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}'**
  String annotationsSaved(String name);

  /// No description provided for @annotationsSelectFirst.
  ///
  /// In en, this message translates to:
  /// **'Tap an annotation to select it.'**
  String get annotationsSelectFirst;

  /// No description provided for @annotationsDiscardPrompt.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes? The document is unchanged either way.'**
  String get annotationsDiscardPrompt;

  /// No description provided for @signMode.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get signMode;

  /// No description provided for @signChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a signature'**
  String get signChoose;

  /// No description provided for @signNone.
  ///
  /// In en, this message translates to:
  /// **'No signatures yet. Draw one to get started.'**
  String get signNone;

  /// No description provided for @signAdd.
  ///
  /// In en, this message translates to:
  /// **'New signature'**
  String get signAdd;

  /// No description provided for @signDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw your signature'**
  String get signDraw;

  /// No description provided for @signClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get signClear;

  /// No description provided for @signSave.
  ///
  /// In en, this message translates to:
  /// **'Save signature'**
  String get signSave;

  /// No description provided for @signLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get signLabel;

  /// No description provided for @signLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Full, Initials…'**
  String get signLabelHint;

  /// No description provided for @signRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get signRename;

  /// No description provided for @signDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get signDelete;

  /// No description provided for @signPlaceHint.
  ///
  /// In en, this message translates to:
  /// **'Drag a box where the signature should go.'**
  String get signPlaceHint;

  /// No description provided for @signSaved.
  ///
  /// In en, this message translates to:
  /// **'Signed {name}'**
  String signSaved(String name);

  /// No description provided for @signDiscardPrompt.
  ///
  /// In en, this message translates to:
  /// **'Discard this signature placement? The document is unchanged either way.'**
  String get signDiscardPrompt;

  /// No description provided for @noteMode.
  ///
  /// In en, this message translates to:
  /// **'Sticky note'**
  String get noteMode;

  /// No description provided for @noteText.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteText;

  /// No description provided for @noteHint.
  ///
  /// In en, this message translates to:
  /// **'What do you want to say?'**
  String get noteHint;

  /// No description provided for @notePlaceHint.
  ///
  /// In en, this message translates to:
  /// **'Tap where the note should go.'**
  String get notePlaceHint;

  /// No description provided for @noteEmpty.
  ///
  /// In en, this message translates to:
  /// **'A note needs some text.'**
  String get noteEmpty;

  /// No description provided for @stampMode.
  ///
  /// In en, this message translates to:
  /// **'Stamp'**
  String get stampMode;

  /// No description provided for @stampPlaceHint.
  ///
  /// In en, this message translates to:
  /// **'Tap where the stamp should go.'**
  String get stampPlaceHint;

  /// No description provided for @stampApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get stampApproved;

  /// No description provided for @stampRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get stampRejected;

  /// No description provided for @stampDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get stampDraft;

  /// No description provided for @stampConfidential.
  ///
  /// In en, this message translates to:
  /// **'Confidential'**
  String get stampConfidential;

  /// No description provided for @stampReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get stampReviewed;

  /// No description provided for @stampUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get stampUrgent;

  /// No description provided for @watermarkMode.
  ///
  /// In en, this message translates to:
  /// **'Watermark'**
  String get watermarkMode;

  /// No description provided for @watermarkText.
  ///
  /// In en, this message translates to:
  /// **'Watermark text'**
  String get watermarkText;

  /// No description provided for @watermarkHint.
  ///
  /// In en, this message translates to:
  /// **'DRAFT, CONFIDENTIAL…'**
  String get watermarkHint;

  /// No description provided for @watermarkSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get watermarkSize;

  /// No description provided for @watermarkOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get watermarkOpacity;

  /// No description provided for @watermarkDiagonal.
  ///
  /// In en, this message translates to:
  /// **'Diagonal'**
  String get watermarkDiagonal;

  /// No description provided for @watermarkHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get watermarkHorizontal;

  /// No description provided for @watermarkApply.
  ///
  /// In en, this message translates to:
  /// **'Apply to every page'**
  String get watermarkApply;

  /// No description provided for @watermarkApplied.
  ///
  /// In en, this message translates to:
  /// **'Watermarked {name}'**
  String watermarkApplied(String name);

  /// No description provided for @watermarkEmpty.
  ///
  /// In en, this message translates to:
  /// **'A watermark needs some text.'**
  String get watermarkEmpty;

  /// No description provided for @redactMode.
  ///
  /// In en, this message translates to:
  /// **'Redact'**
  String get redactMode;

  /// No description provided for @redactHint.
  ///
  /// In en, this message translates to:
  /// **'Drag over anything you want removed.'**
  String get redactHint;

  /// No description provided for @redactApply.
  ///
  /// In en, this message translates to:
  /// **'Apply redactions'**
  String get redactApply;

  /// No description provided for @redactClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get redactClear;

  /// No description provided for @redactNone.
  ///
  /// In en, this message translates to:
  /// **'Draw at least one box first.'**
  String get redactNone;

  /// No description provided for @redactConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply redactions?'**
  String get redactConfirmTitle;

  /// No description provided for @redactConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The content under each box will be removed from the new document. It cannot be recovered from it.'**
  String get redactConfirmBody;

  /// No description provided for @redactConfirmNotCovered.
  ///
  /// In en, this message translates to:
  /// **'Not covered: document title and author, bookmarks, and attachments. Redacted pages become images, so their text is rebuilt and may lose accents or non-Latin characters.'**
  String get redactConfirmNotCovered;

  /// No description provided for @redactConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Redact'**
  String get redactConfirmAction;

  /// No description provided for @redactDone.
  ///
  /// In en, this message translates to:
  /// **'Redacted {name}'**
  String redactDone(String name);

  /// No description provided for @redactDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard redaction boxes?'**
  String get redactDiscardTitle;

  /// No description provided for @redactDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'The boxes you drew have not been applied. The original document is untouched either way.'**
  String get redactDiscardBody;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanTitle;

  /// No description provided for @scanEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pages yet. Take a photo or import images.'**
  String get scanEmpty;

  /// No description provided for @scanCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get scanCamera;

  /// No description provided for @scanImport.
  ///
  /// In en, this message translates to:
  /// **'Import images'**
  String get scanImport;

  /// No description provided for @scanSave.
  ///
  /// In en, this message translates to:
  /// **'Save as PDF'**
  String get scanSave;

  /// No description provided for @scanRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove page'**
  String get scanRemove;

  /// No description provided for @scanNoTextWarning.
  ///
  /// In en, this message translates to:
  /// **'A scan has no text layer. It cannot be searched, and its text cannot be selected or copied.'**
  String get scanNoTextWarning;

  /// No description provided for @scanPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String scanPageLabel(int number);

  /// No description provided for @scanSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}'**
  String scanSaved(String name);

  /// No description provided for @scanDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this scan?'**
  String get scanDiscardTitle;

  /// No description provided for @scanDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'The pages you captured have not been saved.'**
  String get scanDiscardBody;

  /// No description provided for @scanUnsupportedImage.
  ///
  /// In en, this message translates to:
  /// **'That image is not a baseline JPEG and cannot be added.'**
  String get scanUnsupportedImage;

  /// No description provided for @ocrMode.
  ///
  /// In en, this message translates to:
  /// **'Make searchable (OCR)'**
  String get ocrMode;

  /// No description provided for @ocrRunning.
  ///
  /// In en, this message translates to:
  /// **'Reading text… this can take a while.'**
  String get ocrRunning;

  /// No description provided for @ocrDone.
  ///
  /// In en, this message translates to:
  /// **'Made {name} searchable'**
  String ocrDone(String name);

  /// No description provided for @ocrNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No text was recognised in this document.'**
  String get ocrNothingFound;

  /// No description provided for @ocrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'OCR is not available on this platform.'**
  String get ocrUnavailable;

  /// No description provided for @ocrApproximate.
  ///
  /// In en, this message translates to:
  /// **'On this platform Folio can read the words but not where they sit, so search will find them but highlight only the right area.'**
  String get ocrApproximate;

  /// No description provided for @compressMode.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get compressMode;

  /// No description provided for @compressChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking what can be saved…'**
  String get compressChecking;

  /// No description provided for @compressNothing.
  ///
  /// In en, this message translates to:
  /// **'This document is already well compressed. Nothing worth saving.'**
  String get compressNothing;

  /// No description provided for @compressOffer.
  ///
  /// In en, this message translates to:
  /// **'Can save {saved} ({percent}%). The pages will look exactly the same.'**
  String compressOffer(String saved, String percent);

  /// No description provided for @compressApply.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get compressApply;

  /// No description provided for @compressDone.
  ///
  /// In en, this message translates to:
  /// **'Compressed to {name}'**
  String compressDone(String name);

  /// No description provided for @compressLossless.
  ///
  /// In en, this message translates to:
  /// **'Folio only compresses losslessly: nothing is removed and no image quality is reduced.'**
  String get compressLossless;

  /// No description provided for @batchTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply to {count} documents'**
  String batchTitle(int count);

  /// No description provided for @batchCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get batchCompress;

  /// No description provided for @batchOcr.
  ///
  /// In en, this message translates to:
  /// **'Make searchable (OCR)'**
  String get batchOcr;

  /// No description provided for @batchWatermark.
  ///
  /// In en, this message translates to:
  /// **'Watermark'**
  String get batchWatermark;

  /// No description provided for @batchProtect.
  ///
  /// In en, this message translates to:
  /// **'Protect with password'**
  String get batchProtect;

  /// No description provided for @batchRunning.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String batchRunning(int done, int total);

  /// No description provided for @batchCancel.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get batchCancel;

  /// No description provided for @batchStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped. Documents already finished were kept.'**
  String get batchStopped;

  /// No description provided for @batchDoneAll.
  ///
  /// In en, this message translates to:
  /// **'All {count} done'**
  String batchDoneAll(int count);

  /// No description provided for @batchDoneSome.
  ///
  /// In en, this message translates to:
  /// **'{done} done, {skipped} skipped'**
  String batchDoneSome(int done, int skipped);

  /// No description provided for @batchDoneNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing was produced'**
  String get batchDoneNone;

  /// No description provided for @batchSkipNothing.
  ///
  /// In en, this message translates to:
  /// **'{count} had nothing to gain'**
  String batchSkipNothing(int count);

  /// No description provided for @batchSkipFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} could not be processed'**
  String batchSkipFailed(int count);

  /// No description provided for @batchNewDocuments.
  ///
  /// In en, this message translates to:
  /// **'Each result is a new document. Your originals are untouched.'**
  String get batchNewDocuments;

  /// No description provided for @batchSlowWarning.
  ///
  /// In en, this message translates to:
  /// **'This reads every page and can take several minutes.'**
  String get batchSlowWarning;

  /// No description provided for @automationTitle.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get automationTitle;

  /// No description provided for @automationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rules yet. A rule runs when you add a document to your library.'**
  String get automationEmpty;

  /// No description provided for @automationAdd.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get automationAdd;

  /// No description provided for @automationDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete rule'**
  String get automationDelete;

  /// No description provided for @automationWhen.
  ///
  /// In en, this message translates to:
  /// **'When a document is added'**
  String get automationWhen;

  /// No description provided for @automationNameContains.
  ///
  /// In en, this message translates to:
  /// **'and its name contains (optional)'**
  String get automationNameContains;

  /// No description provided for @automationMinSize.
  ///
  /// In en, this message translates to:
  /// **'and it is at least this many KB (optional)'**
  String get automationMinSize;

  /// No description provided for @automationWatermarkText.
  ///
  /// In en, this message translates to:
  /// **'Watermark text'**
  String get automationWatermarkText;

  /// No description provided for @automationInPlace.
  ///
  /// In en, this message translates to:
  /// **'Compressing and OCR replace the document. Watermarking makes a new one, because it changes how the page looks.'**
  String get automationInPlace;

  /// No description provided for @automationNoProtect.
  ///
  /// In en, this message translates to:
  /// **'Protecting with a password cannot be automated: a rule that ran on its own would have to store your password.'**
  String get automationNoProtect;

  /// No description provided for @automationRuleCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress it'**
  String get automationRuleCompress;

  /// No description provided for @automationRuleOcr.
  ///
  /// In en, this message translates to:
  /// **'Make it searchable'**
  String get automationRuleOcr;

  /// No description provided for @automationRuleWatermark.
  ///
  /// In en, this message translates to:
  /// **'Watermark it'**
  String get automationRuleWatermark;

  /// No description provided for @printAction.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get printAction;

  /// No description provided for @shareAction.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareAction;

  /// No description provided for @printProtected.
  ///
  /// In en, this message translates to:
  /// **'A protected document cannot be printed. Folio does not hand your password to the printing service.'**
  String get printProtected;

  /// No description provided for @shareLeavesDevice.
  ///
  /// In en, this message translates to:
  /// **'Sharing sends this document out of Folio. Everything else Folio does stays on your device.'**
  String get shareLeavesDevice;

  /// No description provided for @shareWhich.
  ///
  /// In en, this message translates to:
  /// **'Sharing {name}'**
  String shareWhich(String name);

  /// No description provided for @printFailed.
  ///
  /// In en, this message translates to:
  /// **'The printing service could not be reached.'**
  String get printFailed;

  /// No description provided for @viewerLeaveMode.
  ///
  /// In en, this message translates to:
  /// **'Back to reading'**
  String get viewerLeaveMode;

  /// No description provided for @searchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get searchClear;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'Match system'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Workflow'**
  String get settingsWorkflow;

  /// No description provided for @settingsAutomationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rules that run when you add a document'**
  String get settingsAutomationSubtitle;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Folio works entirely on your device. It has no account, no cloud and no telemetry, and the release build cannot reach the network at all. Printing and sharing are the only two features that send a document elsewhere, and both are things you start yourself.'**
  String get settingsPrivacyBody;

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsLicenses;

  /// No description provided for @settingsLicensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every library Folio is built on'**
  String get settingsLicensesSubtitle;

  /// No description provided for @protectMode.
  ///
  /// In en, this message translates to:
  /// **'Protect with password'**
  String get protectMode;

  /// No description provided for @protectPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get protectPassword;

  /// No description provided for @protectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get protectConfirm;

  /// No description provided for @protectMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match.'**
  String get protectMismatch;

  /// No description provided for @protectApply.
  ///
  /// In en, this message translates to:
  /// **'Protect'**
  String get protectApply;

  /// No description provided for @protectPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Restrict what readers can do'**
  String get protectPermissionsTitle;

  /// No description provided for @protectAllowPrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get protectAllowPrinting;

  /// No description provided for @protectAllowCopying.
  ///
  /// In en, this message translates to:
  /// **'Copying text'**
  String get protectAllowCopying;

  /// No description provided for @protectAllowModifying.
  ///
  /// In en, this message translates to:
  /// **'Changing the document'**
  String get protectAllowModifying;

  /// No description provided for @protectAllowAnnotating.
  ///
  /// In en, this message translates to:
  /// **'Adding comments and filling forms'**
  String get protectAllowAnnotating;

  /// No description provided for @protectOwnerPassword.
  ///
  /// In en, this message translates to:
  /// **'Owner password (optional)'**
  String get protectOwnerPassword;

  /// No description provided for @protectOwnerHint.
  ///
  /// In en, this message translates to:
  /// **'Opens the document with every right, ignoring the restrictions above. Leave it empty to reuse the password above.'**
  String get protectOwnerHint;

  /// No description provided for @protectAdvisory.
  ///
  /// In en, this message translates to:
  /// **'Restrictions are recorded in the document. Most readers honour them, and any reader is free to ignore them.'**
  String get protectAdvisory;

  /// No description provided for @protectWarning.
  ///
  /// In en, this message translates to:
  /// **'Keep this password safe. Folio cannot recover a protected document without it.'**
  String get protectWarning;

  /// No description provided for @protectDone.
  ///
  /// In en, this message translates to:
  /// **'Protected {name}'**
  String protectDone(String name);
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
