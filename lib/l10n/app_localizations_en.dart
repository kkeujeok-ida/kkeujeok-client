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
  String get library => 'Library';

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
}
