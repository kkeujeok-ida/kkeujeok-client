import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Kkeujeok'**
  String get productName;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @openSidebar.
  ///
  /// In en, this message translates to:
  /// **'Open menu'**
  String get openSidebar;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system settings'**
  String get languageSystem;

  /// No description provided for @languageKo.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get languageKo;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @privacyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The privacy policy address is not set.'**
  String get privacyUnavailable;

  /// No description provided for @privacyOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the privacy policy. Please try again.'**
  String get privacyOpenFailed;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in'**
  String get signingIn;

  /// No description provided for @driveNotice.
  ///
  /// In en, this message translates to:
  /// **'Your notes are saved in the Kkeujeok folder of your Google Drive'**
  String get driveNotice;

  /// No description provided for @driveDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Google Drive access was denied.'**
  String get driveDeniedTitle;

  /// No description provided for @driveDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'To save notes in the Kkeujeok folder of your Google Drive, you need to allow access. Kkeujeok can only see files it created.'**
  String get driveDeniedBody;

  /// No description provided for @requestAgain.
  ///
  /// In en, this message translates to:
  /// **'Request again'**
  String get requestAgain;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again'**
  String get networkError;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @disconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect?'**
  String get disconnectTitle;

  /// No description provided for @disconnectBody.
  ///
  /// In en, this message translates to:
  /// **'The note copies and sign-in info on this device will be erased. The note files in your Drive stay as they are.'**
  String get disconnectBody;

  /// No description provided for @disconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting'**
  String get disconnecting;

  /// No description provided for @disconnectDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t erase the note copies on this device. Please try again.'**
  String get disconnectDeleteFailed;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get newNote;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @noteTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get noteTitle;

  /// No description provided for @pageBackground.
  ///
  /// In en, this message translates to:
  /// **'Page background'**
  String get pageBackground;

  /// No description provided for @backgroundPlain.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get backgroundPlain;

  /// No description provided for @backgroundLined.
  ///
  /// In en, this message translates to:
  /// **'Lined'**
  String get backgroundLined;

  /// No description provided for @backgroundGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get backgroundGrid;

  /// No description provided for @backgroundDot.
  ///
  /// In en, this message translates to:
  /// **'Dot'**
  String get backgroundDot;

  /// No description provided for @pageOrientation.
  ///
  /// In en, this message translates to:
  /// **'Page orientation'**
  String get pageOrientation;

  /// No description provided for @orientationPortrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get orientationPortrait;

  /// No description provided for @orientationLandscape.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get orientationLandscape;

  /// No description provided for @noteSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save to this device.'**
  String get noteSaveFailed;

  /// No description provided for @cannotOpen.
  ///
  /// In en, this message translates to:
  /// **'Can\'t open'**
  String get cannotOpen;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Create new'**
  String get addNote;

  /// No description provided for @closeMenu.
  ///
  /// In en, this message translates to:
  /// **'Close menu'**
  String get closeMenu;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your notes'**
  String get loadFailed;

  /// No description provided for @backToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Back to library'**
  String get backToLibrary;

  /// No description provided for @penSlotLabel.
  ///
  /// In en, this message translates to:
  /// **'Pen, {color}, width {width}'**
  String penSlotLabel(String color, String width);

  /// No description provided for @colorBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get colorBlack;

  /// No description provided for @pageSemantics.
  ///
  /// In en, this message translates to:
  /// **'Page {n} of {total}, {orientation}'**
  String pageSemantics(int n, int total, String orientation);

  /// No description provided for @handwriting.
  ///
  /// In en, this message translates to:
  /// **'Handwriting'**
  String get handwriting;

  /// No description provided for @strokeNotAdded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the stroke.'**
  String get strokeNotAdded;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @historyNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t apply that change.'**
  String get historyNotApplied;

  /// No description provided for @moreMenu.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreMenu;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomLevel.
  ///
  /// In en, this message translates to:
  /// **'Zoom {percent}%'**
  String zoomLevel(int percent);

  /// No description provided for @fitWidth.
  ///
  /// In en, this message translates to:
  /// **'Fit width'**
  String get fitWidth;

  /// No description provided for @fitPage.
  ///
  /// In en, this message translates to:
  /// **'Fit page'**
  String get fitPage;

  /// No description provided for @penEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get penEditTitle;

  /// No description provided for @usePressure.
  ///
  /// In en, this message translates to:
  /// **'Use pressure'**
  String get usePressure;

  /// No description provided for @syncLogExport.
  ///
  /// In en, this message translates to:
  /// **'Export sync log'**
  String get syncLogExport;

  /// No description provided for @syncLogExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export the log'**
  String get syncLogExportFailed;

  /// No description provided for @drivePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing Drive'**
  String get drivePreparing;

  /// No description provided for @rootMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t find the Kkeujeok folder in Drive'**
  String get rootMissingTitle;

  /// No description provided for @rootMissingBody.
  ///
  /// In en, this message translates to:
  /// **'The folder was deleted or is in the trash. If you create a new one, the notes on this device are uploaded again. You can keep writing in the meantime.'**
  String get rootMissingBody;

  /// No description provided for @rootMissingCreate.
  ///
  /// In en, this message translates to:
  /// **'Create new'**
  String get rootMissingCreate;

  /// No description provided for @rootMissingLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get rootMissingLater;

  /// No description provided for @rootMissingSignOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get rootMissingSignOut;

  /// No description provided for @driveReauth.
  ///
  /// In en, this message translates to:
  /// **'Please sign in again'**
  String get driveReauth;

  /// No description provided for @driveReauthAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get driveReauthAction;

  /// No description provided for @drivePrepareFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t prepare Drive'**
  String get drivePrepareFailed;

  /// No description provided for @receiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get receiving;

  /// No description provided for @receivingLatest.
  ///
  /// In en, this message translates to:
  /// **'Receiving the latest version'**
  String get receivingLatest;

  /// No description provided for @scanningNotes.
  ///
  /// In en, this message translates to:
  /// **'Checking your notes'**
  String get scanningNotes;

  /// No description provided for @accountMismatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Signed in with a different account'**
  String get accountMismatchTitle;

  /// No description provided for @accountMismatchBody.
  ///
  /// In en, this message translates to:
  /// **'Account {email} has {count, plural, =1{1 change} other{{count} changes}} that weren\'t sent.'**
  String accountMismatchBody(String email, int count);

  /// No description provided for @accountMismatchBodyUnknown.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check whether account {email} has changes that weren\'t sent. Discarding may lose them.'**
  String accountMismatchBodyUnknown(String email);

  /// No description provided for @accountMismatchBack.
  ///
  /// In en, this message translates to:
  /// **'Go back to the previous account'**
  String get accountMismatchBack;

  /// No description provided for @accountMismatchDownload.
  ///
  /// In en, this message translates to:
  /// **'Save as files'**
  String get accountMismatchDownload;

  /// No description provided for @accountMismatchDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard {count, plural, =1{1 change} other{{count} changes}} from the previous account'**
  String accountMismatchDiscard(int count);

  /// No description provided for @accountMismatchDiscardUnknown.
  ///
  /// In en, this message translates to:
  /// **'Discard changes from the previous account'**
  String get accountMismatchDiscardUnknown;

  /// No description provided for @discardAgain.
  ///
  /// In en, this message translates to:
  /// **'Press again to discard'**
  String get discardAgain;

  /// No description provided for @accountMismatchDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the files. Please try again.'**
  String get accountMismatchDownloadFailed;

  /// No description provided for @accountMismatchDownloadNone.
  ///
  /// In en, this message translates to:
  /// **'There are no notes to save.'**
  String get accountMismatchDownloadNone;

  /// No description provided for @accountClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t erase the previous account\'s note copies. Please try again.'**
  String get accountClearFailed;

  /// No description provided for @unsentLogoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Changes weren\'t sent'**
  String get unsentLogoutTitle;

  /// No description provided for @unsentLogoutBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change wasn\'t} other{{count} changes weren\'t}} sent. If you log out, they will be lost.'**
  String unsentLogoutBody(int count);

  /// No description provided for @unsentLogoutBodyUnknown.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for changes that weren\'t sent. If you log out, they may be lost.'**
  String get unsentLogoutBodyUnknown;

  /// No description provided for @unsentLogoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard and log out'**
  String get unsentLogoutConfirm;

  /// No description provided for @unsentDisconnectLine.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change wasn\'t} other{{count} changes weren\'t}} sent.'**
  String unsentDisconnectLine(int count);

  /// No description provided for @unsentDisconnectLineUnknown.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for changes that weren\'t sent.'**
  String get unsentDisconnectLineUnknown;

  /// No description provided for @unsentDisconnectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard and disconnect'**
  String get unsentDisconnectConfirm;

  /// No description provided for @syncStateSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get syncStateSaved;

  /// No description provided for @syncStatePending.
  ///
  /// In en, this message translates to:
  /// **'Waiting to save'**
  String get syncStatePending;

  /// No description provided for @syncStateOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline · Kept on this device'**
  String get syncStateOffline;

  /// No description provided for @syncBadgeOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncBadgeOffline;

  /// No description provided for @syncStateSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get syncStateSaving;

  /// No description provided for @syncStateReceiving.
  ///
  /// In en, this message translates to:
  /// **'Getting the latest'**
  String get syncStateReceiving;

  /// No description provided for @syncStateTwoVersions.
  ///
  /// In en, this message translates to:
  /// **'Two versions'**
  String get syncStateTwoVersions;

  /// No description provided for @syncStateNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Not saved'**
  String get syncStateNotSaved;

  /// No description provided for @syncIndicatorLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync status: {state}. More details'**
  String syncIndicatorLabel(String state);

  /// No description provided for @syncDescSaved.
  ///
  /// In en, this message translates to:
  /// **'All changes are saved to Drive.'**
  String get syncDescSaved;

  /// No description provided for @syncDescPending.
  ///
  /// In en, this message translates to:
  /// **'Saving to Drive soon.'**
  String get syncDescPending;

  /// No description provided for @syncDescOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Changes are kept on this device and saved when you\'re connected.'**
  String get syncDescOffline;

  /// No description provided for @syncDescSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving to Drive.'**
  String get syncDescSaving;

  /// No description provided for @syncDescReceiving.
  ///
  /// In en, this message translates to:
  /// **'Getting the latest version from another device.'**
  String get syncDescReceiving;

  /// No description provided for @syncDescTwoVersions.
  ///
  /// In en, this message translates to:
  /// **'A page was changed on two devices.'**
  String get syncDescTwoVersions;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Changes are kept on this device. Try again or export the sync log.'**
  String get syncErrorBody;

  /// No description provided for @syncQuotaBody.
  ///
  /// In en, this message translates to:
  /// **'Drive is out of space. Changes are kept on this device.'**
  String get syncQuotaBody;

  /// No description provided for @syncManageDrive.
  ///
  /// In en, this message translates to:
  /// **'Manage Drive storage'**
  String get syncManageDrive;

  /// No description provided for @syncOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the page.'**
  String get syncOpenFailed;

  /// No description provided for @syncReauthBanner.
  ///
  /// In en, this message translates to:
  /// **'Your sign-in expired. Changes are kept on this device.'**
  String get syncReauthBanner;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @deletedBanner.
  ///
  /// In en, this message translates to:
  /// **'This note was deleted on another device.'**
  String get deletedBanner;

  /// No description provided for @deletedRevive.
  ///
  /// In en, this message translates to:
  /// **'Bring it back'**
  String get deletedRevive;

  /// No description provided for @revivedSnack.
  ///
  /// In en, this message translates to:
  /// **'This note was deleted on another device but had changes not sent yet, so it was brought back.'**
  String get revivedSnack;

  /// No description provided for @newVersionBanner.
  ///
  /// In en, this message translates to:
  /// **'This note was made in a newer version. Update the app to edit it.'**
  String get newVersionBanner;

  /// No description provided for @cannotOpenBody.
  ///
  /// In en, this message translates to:
  /// **'This note file cannot be read. The file was left as it is.'**
  String get cannotOpenBody;

  /// No description provided for @cannotOpenViewInDrive.
  ///
  /// In en, this message translates to:
  /// **'View in Drive'**
  String get cannotOpenViewInDrive;

  /// No description provided for @cannotOpenDownload.
  ///
  /// In en, this message translates to:
  /// **'Download as file'**
  String get cannotOpenDownload;

  /// No description provided for @conflictBanner.
  ///
  /// In en, this message translates to:
  /// **'You edited this page on another device too. It is read-only until you choose.'**
  String get conflictBanner;

  /// No description provided for @conflictBannerDeleted.
  ///
  /// In en, this message translates to:
  /// **'A page was deleted on another device. This device\'s version is kept until you choose.'**
  String get conflictBannerDeleted;

  /// No description provided for @conflictResolveAction.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get conflictResolveAction;

  /// No description provided for @conflictReadOnlyBlocked.
  ///
  /// In en, this message translates to:
  /// **'This page is read-only.'**
  String get conflictReadOnlyBlocked;

  /// No description provided for @conflictFound.
  ///
  /// In en, this message translates to:
  /// **'Page {n} was edited on both devices. It is read-only until you choose.'**
  String conflictFound(int n);

  /// No description provided for @conflictFoundDeleted.
  ///
  /// In en, this message translates to:
  /// **'Page {n} was deleted on another device. This device\'s version is kept until you choose.'**
  String conflictFoundDeleted(int n);

  /// No description provided for @conflictPageSemantics.
  ///
  /// In en, this message translates to:
  /// **'Read-only, page edited on both devices'**
  String get conflictPageSemantics;

  /// No description provided for @conflictNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'A page was edited on both devices'**
  String get conflictNotificationTitle;

  /// No description provided for @conflictNotificationChannel.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get conflictNotificationChannel;
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
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
