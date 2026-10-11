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
  String get library => 'Notes';

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

  @override
  String get signInWithGoogle => 'Google로 로그인';

  @override
  String get signingIn => '로그인 중';

  @override
  String get driveNotice => '노트는 내 Google Drive의 Kkeujeok 폴더에 저장돼요';

  @override
  String get driveDeniedTitle => 'Google Drive 접근이 거부됐어요.';

  @override
  String get driveDeniedBody =>
      '노트를 내 Google Drive의 Kkeujeok 폴더에 저장하려면 접근을 허용해야 해요. Kkeujeok이 만든 파일만 볼 수 있어요.';

  @override
  String get requestAgain => '다시 요청';

  @override
  String get networkError => '연결을 확인하고 다시 시도해 주세요';

  @override
  String get retry => '다시 시도';

  @override
  String get logOut => '로그아웃';

  @override
  String get disconnect => '연결 해제';

  @override
  String get cancel => '취소';

  @override
  String get disconnectTitle => '연결을 해제할까요?';

  @override
  String get disconnectBody =>
      '이 기기의 노트 사본과 로그인 정보가 지워져요. Drive의 노트 파일은 그대로 남아요.';

  @override
  String get disconnecting => '연결을 해제하는 중';

  @override
  String get disconnectDeleteFailed => '이 기기의 노트 사본을 지우지 못했어요. 다시 시도해 주세요.';

  @override
  String get newNote => '새 노트';

  @override
  String get create => '만들기';

  @override
  String get noteTitle => '제목';

  @override
  String get pageBackground => '페이지 배경';

  @override
  String get backgroundPlain => '무지';

  @override
  String get backgroundLined => '줄';

  @override
  String get backgroundGrid => '모눈';

  @override
  String get backgroundDot => '점';

  @override
  String get pageOrientation => '페이지 방향';

  @override
  String get orientationPortrait => '세로';

  @override
  String get orientationLandscape => '가로';

  @override
  String get noteSaveFailed => '이 기기에 저장하지 못했어요.';

  @override
  String get cannotOpen => '열 수 없음';

  @override
  String get addNote => '새로 만들기';

  @override
  String get closeMenu => '메뉴 닫기';

  @override
  String get loadFailed => '목록을 불러오지 못했어요';

  @override
  String get backToLibrary => 'Notes로';

  @override
  String penSlotLabel(String color, String width) {
    return '펜, $color, 두께 $width';
  }

  @override
  String get colorBlack => '검정';

  @override
  String pageSemantics(int n, int total, String orientation) {
    return '$n페이지 / $total, $orientation';
  }

  @override
  String get handwriting => '손글씨';

  @override
  String get strokeNotAdded => '획을 추가하지 못했어요.';

  @override
  String get undo => '실행 취소';

  @override
  String get redo => '다시 실행';

  @override
  String get historyNotApplied => '변경을 적용하지 못했어요.';

  @override
  String get moreMenu => '더 보기';

  @override
  String get zoomOut => '축소';

  @override
  String get zoomIn => '확대';

  @override
  String zoomLevel(int percent) {
    return '배율 $percent%';
  }

  @override
  String get fitWidth => '너비 맞춤';

  @override
  String get fitPage => '페이지 맞춤';

  @override
  String get penEditTitle => '펜';

  @override
  String get usePressure => '필압 반영';
}
