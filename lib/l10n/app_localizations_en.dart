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

  @override
  String get collectionsAll => 'All';

  @override
  String get collectionNew => 'New folder';

  @override
  String get collectionNameHint => 'Folder name';

  @override
  String get moveToAction => 'Move to';

  @override
  String get moveToRoot => 'Library root';

  @override
  String get saveAsAction => 'Save a copy';

  @override
  String get exportSuccess => 'Copy saved';

  @override
  String get deleteFolderAction => 'Delete folder';

  @override
  String get renameFolderAction => 'Rename folder';

  @override
  String get deleteFolderExplain =>
      'Documents in this folder return to the library root. Nothing is deleted.';

  @override
  String get createAction => 'Create';

  @override
  String get noDocumentsInFolder => 'This folder is empty.';

  @override
  String get errorEmptyDocumentTitle => 'Nothing to save.';

  @override
  String get errorEmptyDocumentBody =>
      'This document has no pages left. Add or restore a page before saving.';

  @override
  String get errorInvalidPageRangeTitle => 'That page range isn\'t valid.';

  @override
  String get errorInvalidPageRangeBody =>
      'Check the page numbers and try again.';

  @override
  String get pagesMode => 'Pages';

  @override
  String get readMode => 'Read';

  @override
  String pagesSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get pagesSelectAll => 'Select all';

  @override
  String get pagesClearSelection => 'Clear selection';

  @override
  String get pagesRotateLeft => 'Rotate left';

  @override
  String get pagesRotateRight => 'Rotate right';

  @override
  String get pagesDelete => 'Delete pages';

  @override
  String get pagesDuplicate => 'Duplicate pages';

  @override
  String get pagesExtract => 'Extract to new document';

  @override
  String get pagesInsert => 'Insert pages from…';

  @override
  String get pagesUndo => 'Undo';

  @override
  String get pagesRedo => 'Redo';

  @override
  String get pagesApply => 'Save as new document';

  @override
  String get pagesDiscard => 'Discard changes';

  @override
  String get pagesDiscardPrompt =>
      'Discard your page changes? The original document is untouched either way.';

  @override
  String pagesApplied(String name) {
    return 'Saved as $name';
  }

  @override
  String get pagesSplit => 'Split document';

  @override
  String get pagesMerge => 'Merge documents';

  @override
  String get pagesEmptyWarning => 'A document must have at least one page.';

  @override
  String get splitEveryPage => 'Every page becomes its own document';

  @override
  String get splitByRanges => 'Custom ranges';

  @override
  String get splitRangeHint => 'e.g. 1-3, 7, 10-12';

  @override
  String splitOutputCount(int count) {
    return '$count documents will be created';
  }

  @override
  String get splitConfirm => 'Split';

  @override
  String get librarySelectMode => 'Select documents';

  @override
  String get libraryMergeSelected => 'Merge selected';

  @override
  String get libraryExitSelect => 'Cancel';

  @override
  String get mergeNeedsTwo => 'Select at least two documents to merge.';

  @override
  String get insertChooseDocument => 'Choose a document to insert';

  @override
  String get insertNoOtherDocuments =>
      'There are no other documents to insert.';

  @override
  String get errorUnsupportedPdfStructureTitle =>
      'Can\'t add markup to this PDF.';

  @override
  String get errorUnsupportedPdfStructureBody =>
      'It uses a newer PDF structure this app can\'t safely modify yet. The document is unchanged.';

  @override
  String get markupMode => 'Markup';

  @override
  String get markupHighlight => 'Highlight';

  @override
  String get markupUnderline => 'Underline';

  @override
  String get markupStrikeOut => 'Strikethrough';

  @override
  String get markupUndo => 'Undo markup';

  @override
  String get markupSave => 'Save with markup';

  @override
  String markupCount(int count) {
    return '$count marked';
  }

  @override
  String markupSaved(String name) {
    return 'Saved as $name';
  }

  @override
  String get markupSelectFirst => 'Select some text to mark it up.';

  @override
  String get markupDiscardPrompt =>
      'Discard your markup? The original document is untouched either way.';

  @override
  String get drawMode => 'Draw';

  @override
  String get drawPen => 'Pen';

  @override
  String get drawRectangle => 'Rectangle';

  @override
  String get drawOval => 'Oval';

  @override
  String get drawLine => 'Line';

  @override
  String get drawArrow => 'Arrow';

  @override
  String get drawColour => 'Colour';

  @override
  String get drawThickness => 'Thickness';

  @override
  String get drawUndo => 'Undo';

  @override
  String get drawSave => 'Save with drawings';

  @override
  String get drawDiscardPrompt =>
      'Discard your drawings? The original document is untouched either way.';

  @override
  String get annotateMode => 'Annotate';
}
