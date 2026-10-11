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
