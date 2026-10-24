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
      'Delete this note? It moves to the Drive trash. You can restore it from Drive.';

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
  String get lassoTool => 'Lasso';

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
}
