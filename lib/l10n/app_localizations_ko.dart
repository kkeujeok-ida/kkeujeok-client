// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get productName => 'Kkeujeok';

  @override
  String get library => '서재';

  @override
  String get settings => '설정';

  @override
  String get openSidebar => '메뉴 열기';

  @override
  String get language => '언어';

  @override
  String get languageSystem => '시스템 설정 따름';

  @override
  String get languageKo => '한국어';

  @override
  String get languageEn => 'English';

  @override
  String get privacyPolicy => '개인정보처리방침';

  @override
  String get privacyUnavailable => '개인정보처리방침 주소가 설정되지 않았어요.';

  @override
  String get privacyOpenFailed => '개인정보처리방침을 열지 못했어요. 다시 시도해 주세요.';
}
