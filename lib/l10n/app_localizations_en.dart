// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get productName => 'Kkeujeok';

  @override
  String get library => 'Notes';

  @override
  String get viewLabel => 'View';

  @override
  String get viewList => 'list';

  @override
  String get viewGrid => 'grid';

  @override
  String get viewSmall => 'Small';

  @override
  String get viewStandard => 'Standard';

  @override
  String get viewLarge => 'Large';

  @override
  String get sortNameAsc => 'Name (A-Z)';

  @override
  String get sortNameDesc => 'Name (Z-A)';

  @override
  String get sortCreatedDesc => 'Created (newest first)';

  @override
  String get sortCreatedAsc => 'Created (oldest first)';

  @override
  String get sortEditedDesc => 'Edited (newest first)';

  @override
  String get sortEditedAsc => 'Edited (oldest first)';

  @override
  String get settings => 'Settings';

  @override
  String get openSidebar => 'Open menu';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow system settings';

  @override
  String get languageKo => '한국어';

  @override
  String get languageEn => 'English';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get privacyUnavailable => 'The privacy policy address is not set.';

  @override
  String get privacyOpenFailed =>
      'Couldn\'t open the privacy policy. Please try again.';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signingIn => 'Signing in';

  @override
  String get driveNotice =>
      'Your notes are saved in the Kkeujeok folder of your Google Drive';

  @override
  String get driveDeniedTitle => 'Google Drive access was denied.';

  @override
  String get driveDeniedBody =>
      'To save notes in the Kkeujeok folder of your Google Drive, you need to allow access. Kkeujeok can only see files it created.';

  @override
  String get requestAgain => 'Request again';

  @override
  String get networkError => 'Check your connection and try again';

  @override
  String get retry => 'Try again';

  @override
  String get logOut => 'Log out';

  @override
  String get logOutConfirmTitle => 'Log out?';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get cancel => 'Cancel';

  @override
  String get disconnectTitle => 'Disconnect?';

  @override
  String get disconnectBody =>
      'The note copies and sign-in info on this device will be erased. The note files in your Drive stay as they are.';

  @override
  String get disconnecting => 'Disconnecting';

  @override
  String get disconnectDeleteFailed =>
      'Couldn\'t erase the note copies on this device. Please try again.';

  @override
  String get newNote => 'New note';

  @override
  String get create => 'Create';

  @override
  String get noteTitle => 'Title';

  @override
  String get pageBackground => 'Page background';

  @override
  String get backgroundPlain => 'Plain';

  @override
  String get backgroundLined => 'Lined';

  @override
  String get backgroundGrid => 'Grid';

  @override
  String get backgroundDot => 'Dot';

  @override
  String get pageOrientation => 'Page orientation';

  @override
  String get orientationPortrait => 'Portrait';

  @override
  String get orientationLandscape => 'Landscape';

  @override
  String get noteSaveFailed => 'Couldn\'t save to this device.';

  @override
  String get cannotOpen => 'Can\'t open';

  @override
  String get addNote => 'Create new';

  @override
  String get closeMenu => 'Close menu';

  @override
  String get loadFailed => 'Couldn\'t load your notes';

  @override
  String get backToLibrary => 'Back to library';

  @override
  String penSlotLabel(String color, String width) {
    return 'Pen, $color, width $width';
  }

  @override
  String get colorBlack => 'Black';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorYellow => 'Yellow';

  @override
  String get colorCustom => 'Custom';

  @override
  String highlighterSlotLabel(String color, String width) {
    return 'Highlighter, $color, width $width';
  }

  @override
  String get addPenSlot => 'Add pen slot';

  @override
  String get deletePenSlot => 'Delete tool';

  @override
  String get penSlotDeleted => 'Tool deleted';

  @override
  String get moveSlotEarlier => 'Move earlier';

  @override
  String get moveSlotLater => 'Move later';

  @override
  String get scrollSlotsBack => 'Show earlier slots';

  @override
  String get scrollSlotsForward => 'Show later slots';

  @override
  String pageSemantics(int n, int total, String orientation) {
    return 'Page $n of $total, $orientation';
  }

  @override
  String get handwriting => 'Handwriting';

  @override
  String get strokeNotAdded => 'Couldn\'t add the stroke.';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get historyNotApplied => 'Couldn\'t apply that change.';

  @override
  String get moreMenu => 'More';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String zoomLevel(int percent) {
    return 'Zoom $percent%';
  }

  @override
  String get fitWidth => 'Fit width';

  @override
  String get fitPage => 'Fit page';

  @override
  String get penEditTitle => 'Pen';

  @override
  String get usePressure => 'Use pressure';

  @override
  String get syncLogExport => 'Export sync log';

  @override
  String get syncLogExportFailed => 'Couldn\'t export the log';

  @override
  String get penDiagTitle => 'Pen input diagnostic';

  @override
  String get penDiagHint =>
      'Touch, press the pen button, or use the eraser end inside the box below.';

  @override
  String get penDiagEmpty => 'No events yet';

  @override
  String get penDiagCopy => 'Copy events';

  @override
  String get penDiagCopied => 'Copied';

  @override
  String get drivePreparing => 'Preparing Drive';

  @override
  String get rootMissingTitle => 'Can\'t find the Kkeujeok folder in Drive';

  @override
  String get rootMissingBody =>
      'The folder was deleted or is in the trash. If you create a new one, the notes on this device are uploaded again. You can keep writing in the meantime.';

  @override
  String get rootMissingCreate => 'Create new';

  @override
  String get rootMissingLater => 'Later';

  @override
  String get rootMissingSignOut => 'Log out';

  @override
  String get driveReauth => 'Please sign in again';

  @override
  String get driveReauthAction => 'Sign in again';

  @override
  String get drivePrepareFailed => 'Couldn\'t prepare Drive';

  @override
  String get receiving => 'Receiving';

  @override
  String get receivingLatest => 'Receiving the latest version';

  @override
  String get scanningNotes => 'Checking your notes';

  @override
  String get accountMismatchTitle => 'Signed in with a different account';

  @override
  String accountMismatchBody(String email, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return 'Account $email has $_temp0 that weren\'t sent.';
  }

  @override
  String accountMismatchBodyUnknown(String email) {
    return 'Couldn\'t check whether account $email has changes that weren\'t sent. Discarding may lose them.';
  }

  @override
  String get accountMismatchBack => 'Go back to the previous account';

  @override
  String get accountMismatchDownload => 'Save as files';

  @override
  String accountMismatchDiscard(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return 'Discard $_temp0 from the previous account';
  }

  @override
  String get accountMismatchDiscardUnknown =>
      'Discard changes from the previous account';

  @override
  String get discardAgain => 'Press again to discard';

  @override
  String get accountMismatchDownloadFailed =>
      'Couldn\'t save the files. Please try again.';

  @override
  String get accountMismatchDownloadNone => 'There are no notes to save.';

  @override
  String accountMismatchDownloadSkipped(int skipped, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total notes',
      one: '1 note',
    );
    return 'Couldn\'t save $skipped of $_temp0.';
  }

  @override
  String get accountClearFailed =>
      'Couldn\'t erase the previous account\'s note copies. Please try again.';

  @override
  String get unsentLogoutTitle => 'Changes weren\'t sent';

  @override
  String unsentLogoutBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes weren\'t',
      one: '1 change wasn\'t',
    );
    return '$_temp0 sent. If you log out, they will be lost.';
  }

  @override
  String get unsentLogoutBodyUnknown =>
      'Couldn\'t check for changes that weren\'t sent. If you log out, they may be lost.';

  @override
  String get unsentLogoutConfirm => 'Discard and log out';

  @override
  String unsentDisconnectLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes weren\'t',
      one: '1 change wasn\'t',
    );
    return '$_temp0 sent.';
  }

  @override
  String get unsentDisconnectLineUnknown =>
      'Couldn\'t check for changes that weren\'t sent.';

  @override
  String get unsentDisconnectConfirm => 'Discard and disconnect';

  @override
  String get syncStateSaved => 'Saved';

  @override
  String get syncStatePending => 'Waiting to save';

  @override
  String get syncStateOffline => 'Offline · Kept on this device';

  @override
  String get syncBadgeOffline => 'Offline';

  @override
  String get syncStateSaving => 'Saving';

  @override
  String get syncStateReceiving => 'Getting the latest';

  @override
  String get syncStateTwoVersions => 'Two versions';

  @override
  String get syncStateNotSaved => 'Not saved';

  @override
  String syncIndicatorLabel(String state) {
    return 'Sync status: $state. More details';
  }

  @override
  String get syncDescSaved => 'All changes are saved to Drive.';

  @override
  String get syncDescPending => 'Saving to Drive soon.';

  @override
  String get syncDescOffline =>
      'You\'re offline. Changes are kept on this device and saved when you\'re connected.';

  @override
  String get syncDescSaving => 'Saving to Drive.';

  @override
  String get syncDescReceiving =>
      'Getting the latest version from another device.';

  @override
  String get syncDescTwoVersions => 'A page was changed on two devices.';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncErrorBody =>
      'Changes are kept on this device. Try again or export the sync log.';

  @override
  String get syncQuotaBody =>
      'Drive is out of space. Changes are kept on this device.';

  @override
  String get syncManageDrive => 'Manage Drive storage';

  @override
  String get syncOpenFailed => 'Couldn\'t open the page.';

  @override
  String get syncReauthBanner =>
      'Your sign-in expired. Changes are kept on this device.';

  @override
  String get close => 'Close';

  @override
  String get deletedBanner => 'This note was deleted on another device.';

  @override
  String get deletedRevive => 'Bring it back';

  @override
  String get revivedSnack =>
      'This note was deleted on another device but had changes not sent yet, so it was brought back.';

  @override
  String get newVersionBanner =>
      'This note was made in a newer version. Update the app to edit it.';

  @override
  String get cannotOpenBody =>
      'This note file cannot be read. The file was left as it is.';

  @override
  String get cannotOpenViewInDrive => 'View in Drive';

  @override
  String get cannotOpenDownload => 'Download as file';

  @override
  String get conflictBanner =>
      'You edited this page on another device too. It is read-only until you choose.';

  @override
  String get conflictBannerDeleted =>
      'A page was deleted on another device. This device\'s version is kept until you choose.';

  @override
  String get conflictResolveAction => 'Resolve';

  @override
  String get conflictReadOnlyBlocked => 'This page is read-only.';

  @override
  String conflictFound(int n) {
    return 'Page $n was edited on both devices. It is read-only until you choose.';
  }

  @override
  String conflictFoundDeleted(int n) {
    return 'Page $n was deleted on another device. This device\'s version is kept until you choose.';
  }

  @override
  String get conflictPageSemantics => 'Read-only, page edited on both devices';

  @override
  String get conflictNotificationTitle => 'A page was edited on both devices';

  @override
  String get conflictNotificationChannel => 'Conflicts';

  @override
  String get conflictSheetTitle => 'Pages edited on both devices';

  @override
  String conflictSheetProgress(int page, int i, int total) {
    return 'Page $page · $i/$total';
  }

  @override
  String get conflictPrev => 'Previous page';

  @override
  String get conflictNext => 'Next page';

  @override
  String get conflictQuestion => 'Which one do you want to keep?';

  @override
  String get conflictTagThis => 'This device';

  @override
  String get conflictTagOther => 'Other device';

  @override
  String get conflictMoreRecent => 'Newer';

  @override
  String conflictEditedAt(String device, String time) {
    return '$device · $time';
  }

  @override
  String get conflictKeepThis => 'This device version';

  @override
  String get conflictKeepOther => 'Other device version';

  @override
  String get conflictKeepBoth => 'Keep both';

  @override
  String get conflictRecoverNote =>
      'The version you do not keep can be restored from version history for 30 days.';

  @override
  String get conflictLater => 'Decide later';

  @override
  String get conflictDeletedHere => 'Page deleted on this device';

  @override
  String get conflictDeletedOther => 'Page deleted on another device';

  @override
  String get conflictRemovePage => 'Delete page';

  @override
  String get conflictKeepVersion => 'Keep this version';

  @override
  String get conflictRestAllThis => 'Rest: all this device version';

  @override
  String get conflictRestAllOther => 'Rest: all other device version';

  @override
  String conflictRestAllConfirm(int n) {
    return 'Tap again to apply to $n pages';
  }

  @override
  String conflictPreviewSemantics(String tag, int n) {
    return '$tag version of page $n';
  }

  @override
  String conflictResolvedBoth(int n) {
    return 'Page $n: kept both';
  }

  @override
  String conflictResolvedThis(int n) {
    return 'Page $n: kept this device version';
  }

  @override
  String conflictResolvedOther(int n) {
    return 'Page $n: kept the other device version';
  }

  @override
  String conflictResolvedRemove(int n) {
    return 'Page $n: deleted';
  }

  @override
  String conflictResolvedKeep(int n) {
    return 'Page $n: kept';
  }

  @override
  String conflictResolvedAll(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n pages resolved',
      one: '1 page resolved',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolveFailed => 'Could not resolve. Try again.';

  @override
  String get viewModeVertical => 'Vertical scroll';

  @override
  String get viewModeHorizontal => 'Horizontal scroll';

  @override
  String get viewModeTwoPage => 'Two pages';

  @override
  String get versionHistory => 'Version history';

  @override
  String get versionHistoryEmpty =>
      'No earlier versions yet. Refresh to check again.';

  @override
  String get versionHistoryRefresh => 'Refresh';

  @override
  String get versionRestoreChanged =>
      'The note changed in the meantime, so nothing was restored. Press again.';

  @override
  String get versionHistoryOffline =>
      'Version history is available once you are connected.';

  @override
  String get versionHistoryFailed => 'Could not load the version history.';

  @override
  String get versionHistoryLoading => 'Loading version history';

  @override
  String get versionTagConflict => 'Version kept from a conflict';

  @override
  String get versionTagBeforeRestore => 'Before restore';

  @override
  String get versionPreviewUnavailable => 'Preview unavailable';

  @override
  String get versionPreviewSemantics => 'Version preview';

  @override
  String get versionRestore => 'Restore this version';

  @override
  String get versionRestoreConfirm => 'Tap again to switch to this version';

  @override
  String get versionRestoring => 'Restoring';

  @override
  String get versionRestored => 'Restored this version';

  @override
  String get versionRestoreFailed =>
      'Could not restore. Try again in a moment.';

  @override
  String get versionRestoreOffline => 'You can restore once you are connected.';

  @override
  String get versionRestoreNotSaved =>
      'Could not save the current state to Drive, so nothing was restored.';

  @override
  String get versionRestorePinFailed =>
      'Could not mark the version before restore, so nothing was restored.';

  @override
  String get versionRestoreUnreadable => 'This version cannot be read.';

  @override
  String get noteDelete => 'Delete';

  @override
  String get noteDeleteBody =>
      'Delete this note? It moves to the trash, where you can restore it.';

  @override
  String get noteDeleteConfirm => 'Delete';

  @override
  String get ratioLock => 'Lock aspect ratio';

  @override
  String get scaleUp => 'Scale up';

  @override
  String get scaleDown => 'Scale down';

  @override
  String get rotate90 => 'Rotate 90°';

  @override
  String get strokeColor => 'Color';

  @override
  String get strokeWidth => 'Thickness';

  @override
  String get copy => 'Copy';

  @override
  String get cut => 'Cut';

  @override
  String get delete => 'Delete';

  @override
  String get paste => 'Paste';

  @override
  String get selectAll => 'Select all';

  @override
  String get lassoTool => 'Lasso';

  @override
  String get textTool => 'Text';

  @override
  String get eraserTool => 'Eraser';

  @override
  String get eraserOptionsTitle => 'Eraser options';

  @override
  String get eraserModeStroke => 'Stroke';

  @override
  String get eraserModePartial => 'Partial';

  @override
  String get eraserReturnToPen => 'Return to pen when done erasing';

  @override
  String get eraserAnnounceStroke => 'Erase whole strokes';

  @override
  String get eraserAnnouncePartial => 'Partial erase';

  @override
  String get eraseNotApplied => 'Couldn\'t erase.';

  @override
  String get imageTool => 'Image';

  @override
  String get imageFromGallery => 'Gallery';

  @override
  String get imageFromCamera => 'Camera';

  @override
  String get imageTooLarge => 'Images larger than 10 MB cannot be added.';

  @override
  String get imageUnsupported =>
      'This image format cannot be added. Only JPEG, PNG and WebP work.';

  @override
  String get imageConvertFailed =>
      'The image could not be converted, so it was not added.';

  @override
  String get imageConverted => 'Converted to JPEG and added.';

  @override
  String get imageStoreFailed => 'Could not save the image.';

  @override
  String get imagePermissionTitle => 'Permission needed';

  @override
  String get imagePermissionReason =>
      'Adding a photo needs camera or photo access. Allow it in Settings.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get imageSemantics => 'Image';

  @override
  String get imagePendingSemantics => 'waiting to be saved';

  @override
  String get imageDownloading => 'Downloading image';

  @override
  String get imageDownloadFailed => 'Download failed';

  @override
  String get imageRetry => 'Try again';

  @override
  String get fontSize => 'Font size';

  @override
  String fontSizeValue(String size) {
    return 'Font size $size';
  }

  @override
  String get textColor => 'Text color';

  @override
  String get bold => 'Bold';

  @override
  String get italic => 'Italic';

  @override
  String get on => 'on';

  @override
  String get off => 'off';

  @override
  String selectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elements selected',
      one: '1 element selected',
    );
    return '$_temp0';
  }

  @override
  String get colorDarkGray => 'Dark gray';

  @override
  String get colorRed => 'Red';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorTeal => 'Teal';

  @override
  String get colorIndigo => 'Indigo';

  @override
  String get colorPurple => 'Purple';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorBrown => 'Brown';

  @override
  String get colorSky => 'Sky';

  @override
  String get colorLavender => 'Lavender';

  @override
  String get toolPen => 'Pen';

  @override
  String get toolHighlighter => 'Highlighter';

  @override
  String get recentColors => 'Recent';

  @override
  String get widthDecrease => 'Decrease thickness';

  @override
  String get widthIncrease => 'Increase thickness';

  @override
  String get colorPickerApply => 'Apply';

  @override
  String get colorPickerCancel => 'Cancel';

  @override
  String get colorHue => 'Hue';

  @override
  String get colorSaturation => 'Saturation';

  @override
  String get colorBrightness => 'Brightness';

  @override
  String strokeWidthValue(String v) {
    return 'Thickness $v';
  }

  @override
  String customColorSlotLabel(String hex) {
    return 'Custom color $hex';
  }

  @override
  String get visibleToolsTitle => 'Tools shown at once';

  @override
  String get visibleToolsLess => 'Show fewer tools';

  @override
  String get visibleToolsMore => 'Show more tools';

  @override
  String get palettePenTitle => 'Pen and highlighter palette';

  @override
  String get paletteAdd => 'Add color';

  @override
  String get paletteReset => 'Reset to default';

  @override
  String get paletteFull => 'A palette holds at most 18 colors.';

  @override
  String paletteEarlier(String color) {
    return 'Move $color earlier';
  }

  @override
  String paletteLater(String color) {
    return 'Move $color later';
  }

  @override
  String paletteRemove(String color) {
    return 'Remove $color';
  }

  @override
  String get penOnlyTitle => 'Write with pen only';

  @override
  String get penOnlyAuto => 'Auto';

  @override
  String get penOnlyOn => 'On';

  @override
  String get penOnlyOff => 'Off';

  @override
  String get toolbarMove => 'Move toolbar';

  @override
  String get dockTop => 'Top';

  @override
  String get dockLeft => 'Left';

  @override
  String get dockRight => 'Right';

  @override
  String get dockBottom => 'Bottom';

  @override
  String toolbarDocked(String place) {
    return 'Toolbar docked: $place';
  }

  @override
  String noteChip(String title, int n, int total) {
    return '$title · $n/$total';
  }

  @override
  String noteBackTo(String title) {
    return 'Back to ‘$title’';
  }

  @override
  String noteOpened(String title) {
    return '‘$title’ opened';
  }

  @override
  String get noteBackUndo => 'Back';

  @override
  String get pageOverviewOpen => 'Pages';

  @override
  String get pageOverviewTitle => 'Pages';

  @override
  String get pageAdd => 'Add page';

  @override
  String get pageSelect => 'Select';

  @override
  String get pageMenu => 'Page menu';

  @override
  String get pageCurrent => 'Current';

  @override
  String get pageConflictBadge => 'Conflict';

  @override
  String pageOutOfBoundsBadge(int n) {
    return '$n elements outside the page';
  }

  @override
  String get pageLandscape => 'landscape';

  @override
  String get pagePortrait => 'portrait';

  @override
  String pageAdded(int n) {
    return 'Page $n added';
  }

  @override
  String pageDeleted(int n) {
    return 'Page $n deleted';
  }

  @override
  String pageDuplicated(int n) {
    return 'Page $n duplicated';
  }

  @override
  String get pageUndo => 'Undo';

  @override
  String get pageDeleteContentConfirm =>
      'Some of these pages have content. Delete them anyway?';

  @override
  String get pageDuplicate => 'Duplicate';

  @override
  String get pageDelete => 'Delete';

  @override
  String get pagePullMore => 'Keep pulling to add a page';

  @override
  String get pagePullRelease => 'Release to add a page';

  @override
  String pageSelected(int count) {
    return '$count selected';
  }

  @override
  String get pageSelectDone => 'Done';

  @override
  String get pageMoveEarlier => 'Move earlier';

  @override
  String get pageMoveLater => 'Move later';

  @override
  String get pageMoveFirst => 'Move to start';

  @override
  String get pageMoveLast => 'Move to end';

  @override
  String pageMoved(int n, int pos) {
    return 'Page $n moved to position $pos';
  }

  @override
  String pagesMoved(int count) {
    return '$count pages moved';
  }

  @override
  String pagesDeleted(int count) {
    return '$count pages deleted';
  }

  @override
  String pagesDuplicated(int count) {
    return '$count pages duplicated';
  }

  @override
  String get pageBackgroundShort => 'Background';

  @override
  String get pageChangeBackground => 'Change background';

  @override
  String get pageToLandscape => 'Make landscape';

  @override
  String get pageToPortrait => 'Make portrait';

  @override
  String pageBackgroundChanged(int n) {
    return 'Page $n background changed';
  }

  @override
  String pagesBackgroundChanged(int count) {
    return 'Background of $count pages changed';
  }

  @override
  String pageTurnedLandscape(int n) {
    return 'Page $n is now landscape';
  }

  @override
  String pageTurnedPortrait(int n) {
    return 'Page $n is now portrait';
  }

  @override
  String get allNotes => 'All notes';

  @override
  String get folderAdd => 'New folder';

  @override
  String folderMenu(String name) {
    return '$name menu';
  }

  @override
  String get folderNewSub => 'New subfolder';

  @override
  String get folderRename => 'Rename';

  @override
  String get folderMove => 'Move';

  @override
  String get folderDelete => 'Delete';

  @override
  String get folderNameLabel => 'Folder name';

  @override
  String get folderNameTooLong =>
      'A folder name can have up to 100 characters.';

  @override
  String get folderSave => 'Save';

  @override
  String get folderEmpty => 'No notes in this folder';

  @override
  String folderDeleteBody(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'This folder and its $n notes go to the app trash.',
      one: 'This folder and its note go to the app trash.',
      zero: 'This folder goes to the app trash.',
    );
    return '$_temp0';
  }

  @override
  String get folderDeleteConfirm => 'Delete';

  @override
  String get folderTopLevel => 'Top level';

  @override
  String folderMoveTitle(String name) {
    return 'Move \"$name\" to';
  }

  @override
  String folderMoved(String name) {
    return 'Moved \"$name\"';
  }

  @override
  String get folderFailed => 'The folder could not be changed.';

  @override
  String get noteRename => 'Rename';

  @override
  String get noteMove => 'Move';

  @override
  String noteMoveTitle(String name) {
    return 'Move \"$name\" to';
  }

  @override
  String noteMoved(String name) {
    return 'Moved to \"$name\"';
  }

  @override
  String get noteTitleTooLong => 'A note title is 100 characters at most.';

  @override
  String get noteActionFailed => 'Could not change the note.';
}
