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
  String get annotationsMode => 'Edit annotations';

  @override
  String get annotationsEmpty => 'This page has no annotations.';

  @override
  String get annotationsDeleteOnly => 'Delete only';

  @override
  String get annotationsDelete => 'Delete';

  @override
  String get annotationsUndo => 'Undo';

  @override
  String get annotationsSave => 'Save changes';

  @override
  String annotationsSaved(String name) {
    return 'Saved $name';
  }

  @override
  String get annotationsSelectFirst => 'Tap an annotation to select it.';

  @override
  String get annotationsDiscardPrompt =>
      'Discard your changes? The document is unchanged either way.';

  @override
  String get signMode => 'Sign';

  @override
  String get signChoose => 'Choose a signature';

  @override
  String get signNone => 'No signatures yet. Draw one to get started.';

  @override
  String get signAdd => 'New signature';

  @override
  String get signDraw => 'Draw your signature';

  @override
  String get signClear => 'Clear';

  @override
  String get signSave => 'Save signature';

  @override
  String get signLabel => 'Label';

  @override
  String get signLabelHint => 'Full, Initials…';

  @override
  String get signRename => 'Rename';

  @override
  String get signDelete => 'Delete';

  @override
  String get signPlaceHint => 'Drag a box where the signature should go.';

  @override
  String signSaved(String name) {
    return 'Signed $name';
  }

  @override
  String get signDiscardPrompt =>
      'Discard this signature placement? The document is unchanged either way.';

  @override
  String get noteMode => 'Sticky note';

  @override
  String get noteText => 'Note';

  @override
  String get noteHint => 'What do you want to say?';

  @override
  String get notePlaceHint => 'Tap where the note should go.';

  @override
  String get noteEmpty => 'A note needs some text.';

  @override
  String get stampMode => 'Stamp';

  @override
  String get stampPlaceHint => 'Tap where the stamp should go.';

  @override
  String get stampApproved => 'Approved';

  @override
  String get stampRejected => 'Rejected';

  @override
  String get stampDraft => 'Draft';

  @override
  String get stampConfidential => 'Confidential';

  @override
  String get stampReviewed => 'Reviewed';

  @override
  String get stampUrgent => 'Urgent';

  @override
  String get watermarkMode => 'Watermark';

  @override
  String get watermarkText => 'Watermark text';

  @override
  String get watermarkHint => 'DRAFT, CONFIDENTIAL…';

  @override
  String get watermarkSize => 'Size';

  @override
  String get watermarkOpacity => 'Opacity';

  @override
  String get watermarkDiagonal => 'Diagonal';

  @override
  String get watermarkHorizontal => 'Horizontal';

  @override
  String get watermarkApply => 'Apply to every page';

  @override
  String watermarkApplied(String name) {
    return 'Watermarked $name';
  }

  @override
  String get watermarkEmpty => 'A watermark needs some text.';

  @override
  String get redactMode => 'Redact';

  @override
  String get redactHint => 'Drag over anything you want removed.';

  @override
  String get redactApply => 'Apply redactions';

  @override
  String get redactClear => 'Clear';

  @override
  String get redactNone => 'Draw at least one box first.';

  @override
  String get redactConfirmTitle => 'Apply redactions?';

  @override
  String get redactConfirmBody =>
      'The content under each box will be removed from the new document. It cannot be recovered from it.';

  @override
  String get redactConfirmNotCovered =>
      'Not covered: document title and author, bookmarks, and attachments. Redacted pages become images, so their text is rebuilt and may lose accents or non-Latin characters.';

  @override
  String get redactConfirmAction => 'Redact';

  @override
  String redactDone(String name) {
    return 'Redacted $name';
  }

  @override
  String get redactDiscardTitle => 'Discard redaction boxes?';

  @override
  String get redactDiscardBody =>
      'The boxes you drew have not been applied. The original document is untouched either way.';

  @override
  String get scanTitle => 'Scan';

  @override
  String get scanEmpty => 'No pages yet. Take a photo or import images.';

  @override
  String get scanCamera => 'Camera';

  @override
  String get scanImport => 'Import images';

  @override
  String get scanSave => 'Save as PDF';

  @override
  String get scanRemove => 'Remove page';

  @override
  String get scanNoTextWarning =>
      'A scan has no text layer. It cannot be searched, and its text cannot be selected or copied.';

  @override
  String scanPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String scanSaved(String name) {
    return 'Saved $name';
  }

  @override
  String get scanDiscardTitle => 'Discard this scan?';

  @override
  String get scanDiscardBody => 'The pages you captured have not been saved.';

  @override
  String get scanUnsupportedImage =>
      'That image is not a baseline JPEG and cannot be added.';

  @override
  String get ocrMode => 'Make searchable (OCR)';

  @override
  String get ocrRunning => 'Reading text… this can take a while.';

  @override
  String ocrDone(String name) {
    return 'Made $name searchable';
  }

  @override
  String get ocrNothingFound => 'No text was recognised in this document.';

  @override
  String get ocrUnavailable => 'OCR is not available on this platform.';

  @override
  String get ocrApproximate =>
      'On this platform Folio can read the words but not where they sit, so search will find them but highlight only the right area.';

  @override
  String get compressMode => 'Compress';

  @override
  String get compressChecking => 'Checking what can be saved…';

  @override
  String get compressNothing =>
      'This document is already well compressed. Nothing worth saving.';

  @override
  String compressOffer(String saved, String percent) {
    return 'Can save $saved ($percent%). The pages will look exactly the same.';
  }

  @override
  String get compressApply => 'Compress';

  @override
  String compressDone(String name) {
    return 'Compressed to $name';
  }

  @override
  String get compressLossless =>
      'Folio only compresses losslessly: nothing is removed and no image quality is reduced.';

  @override
  String batchTitle(int count) {
    return 'Apply to $count documents';
  }

  @override
  String get batchCompress => 'Compress';

  @override
  String get batchOcr => 'Make searchable (OCR)';

  @override
  String get batchWatermark => 'Watermark';

  @override
  String get batchProtect => 'Protect with password';

  @override
  String batchRunning(int done, int total) {
    return '$done of $total done';
  }

  @override
  String get batchCancel => 'Stop';

  @override
  String get batchStopped => 'Stopped. Documents already finished were kept.';

  @override
  String batchDoneAll(int count) {
    return 'All $count done';
  }

  @override
  String batchDoneSome(int done, int skipped) {
    return '$done done, $skipped skipped';
  }

  @override
  String get batchDoneNone => 'Nothing was produced';

  @override
  String batchSkipNothing(int count) {
    return '$count had nothing to gain';
  }

  @override
  String batchSkipFailed(int count) {
    return '$count could not be processed';
  }

  @override
  String get batchNewDocuments =>
      'Each result is a new document. Your originals are untouched.';

  @override
  String get batchSlowWarning =>
      'This reads every page and can take several minutes.';

  @override
  String get automationTitle => 'Automation';

  @override
  String get automationEmpty =>
      'No rules yet. A rule runs when you add a document to your library.';

  @override
  String get automationAdd => 'Add rule';

  @override
  String get automationDelete => 'Delete rule';

  @override
  String get automationWhen => 'When a document is added';

  @override
  String get automationNameContains => 'and its name contains (optional)';

  @override
  String get automationMinSize => 'and it is at least this many KB (optional)';

  @override
  String get automationWatermarkText => 'Watermark text';

  @override
  String get automationInPlace =>
      'Compressing and OCR replace the document. Watermarking makes a new one, because it changes how the page looks.';

  @override
  String get automationNoProtect =>
      'Protecting with a password cannot be automated: a rule that ran on its own would have to store your password.';

  @override
  String get automationRuleCompress => 'Compress it';

  @override
  String get automationRuleOcr => 'Make it searchable';

  @override
  String get automationRuleWatermark => 'Watermark it';

  @override
  String get printAction => 'Print';

  @override
  String get shareAction => 'Share';

  @override
  String get printProtected =>
      'A protected document cannot be printed. Folio does not hand your password to the printing service.';

  @override
  String get shareLeavesDevice =>
      'Sharing sends this document out of Folio. Everything else Folio does stays on your device.';

  @override
  String shareWhich(String name) {
    return 'Sharing $name';
  }

  @override
  String get printFailed => 'The printing service could not be reached.';

  @override
  String get viewerLeaveMode => 'Back to reading';

  @override
  String get searchClear => 'Clear search';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeSystem => 'Match system';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsWorkflow => 'Workflow';

  @override
  String get settingsAutomationSubtitle =>
      'Rules that run when you add a document';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsPrivacyBody =>
      'Folio works entirely on your device. It has no account, no cloud and no telemetry, and the release build cannot reach the network at all. Printing and sharing are the only two features that send a document elsewhere, and both are things you start yourself.';

  @override
  String get settingsLicenses => 'Open-source licences';

  @override
  String get settingsLicensesSubtitle => 'Every library Folio is built on';

  @override
  String get actionsTitle => 'Actions';

  @override
  String get actionsGroupAnnotate => 'Annotate';

  @override
  String get actionsGroupDocument => 'Document';

  @override
  String get actionsGroupProtect => 'Protect';

  @override
  String get actionsGroupSend => 'Send';

  @override
  String get actionsSendNote => 'Leaves your device';

  @override
  String get actionsGroupView => 'View';

  @override
  String get signAddPhoto => 'Photograph a signature';

  @override
  String get signPhotoHint =>
      'Sign on white paper in good light. Folio removes the paper and keeps the ink; the photo itself is never stored.';

  @override
  String get signPhotoUnusable =>
      'That photo could not be separated into ink and paper. Try again on plain paper in brighter light.';

  @override
  String get signPhotoCamera => 'Camera';

  @override
  String get signPhotoGallery => 'Choose a photo';

  @override
  String get signPhotoLabel => 'Name this signature';

  @override
  String get watermarkRemove => 'Remove watermark';

  @override
  String watermarkRemoved(String name) {
    return 'Removed the watermark from $name';
  }

  @override
  String get watermarkNoneFound =>
      'No watermark that Folio applied. Folio can only remove its own: a mark added by another app leaves nothing it can identify with certainty.';

  @override
  String get protectMode => 'Protect with password';

  @override
  String get protectPassword => 'Password';

  @override
  String get protectConfirm => 'Confirm password';

  @override
  String get protectMismatch => 'The passwords do not match.';

  @override
  String get protectApply => 'Protect';

  @override
  String get protectPermissionsTitle => 'Restrict what readers can do';

  @override
  String get protectAllowPrinting => 'Printing';

  @override
  String get protectAllowCopying => 'Copying text';

  @override
  String get protectAllowModifying => 'Changing the document';

  @override
  String get protectAllowAnnotating => 'Adding comments and filling forms';

  @override
  String get protectOwnerPassword => 'Owner password (optional)';

  @override
  String get protectOwnerHint =>
      'Opens the document with every right, ignoring the restrictions above. Leave it empty to reuse the password above.';

  @override
  String get protectAdvisory =>
      'Restrictions are recorded in the document. Most readers honour them, and any reader is free to ignore them.';

  @override
  String get protectWarning =>
      'Keep this password safe. Folio cannot recover a protected document without it.';

  @override
  String protectDone(String name) {
    return 'Protected $name';
  }
}
