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

  /// No description provided for @pagesMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge documents'**
  String get pagesMerge;

  /// No description provided for @pagesEmptyWarning.
  ///
  /// In en, this message translates to:
  /// **'A document must have at least one page.'**
  String get pagesEmptyWarning;

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
