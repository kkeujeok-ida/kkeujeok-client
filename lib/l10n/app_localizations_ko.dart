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
  String get sortNameAsc => '이름순 (ㄱ-ㅎ)';

  @override
  String get sortNameDesc => '이름순 (ㅎ-ㄱ)';

  @override
  String get sortCreatedDesc => '만든 날짜순 (최신부터)';

  @override
  String get sortCreatedAsc => '만든 날짜순 (오래된 것부터)';

  @override
  String get sortEditedDesc => '수정한 날짜순 (최신부터)';

  @override
  String get sortEditedAsc => '수정한 날짜순 (오래된 것부터)';

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
  String get logOutConfirmTitle => '로그아웃할까요?';

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

  @override
  String get syncLogExport => '동기화 로그 내보내기';

  @override
  String get syncLogExportFailed => '로그를 내보내지 못했어요';

  @override
  String get drivePreparing => 'Drive 준비 중';

  @override
  String get rootMissingTitle => 'Drive의 Kkeujeok 폴더를 찾을 수 없어요';

  @override
  String get rootMissingBody =>
      '폴더가 삭제되었거나 휴지통에 있어요. 새로 만들면 이 기기의 노트가 다시 올라가요. 그동안 노트는 계속 쓸 수 있어요.';

  @override
  String get rootMissingCreate => '새로 만들기';

  @override
  String get rootMissingLater => '나중에';

  @override
  String get rootMissingSignOut => '로그아웃';

  @override
  String get driveReauth => '다시 로그인해 주세요';

  @override
  String get driveReauthAction => '다시 로그인';

  @override
  String get drivePrepareFailed => 'Drive를 준비하지 못했어요';

  @override
  String get receiving => '받는 중';

  @override
  String get receivingLatest => '최신 내용 받는 중';

  @override
  String get scanningNotes => '노트 확인 중';

  @override
  String get accountMismatchTitle => '다른 계정으로 로그인했어요';

  @override
  String accountMismatchBody(String email, int count) {
    return '이전 계정($email)에서 보내지 못한 변경 $count개가 있어요.';
  }

  @override
  String accountMismatchBodyUnknown(String email) {
    return '이전 계정($email)에서 보내지 못한 변경이 있는지 확인하지 못했어요. 버리면 그 변경이 사라질 수 있어요.';
  }

  @override
  String get accountMismatchBack => '이전 계정으로 돌아가기';

  @override
  String get accountMismatchDownload => '파일로 내려받기';

  @override
  String accountMismatchDiscard(int count) {
    return '이전 계정 변경 $count개 버리기';
  }

  @override
  String get accountMismatchDiscardUnknown => '이전 계정 변경 버리기';

  @override
  String get discardAgain => '한 번 더 누르면 버려져요';

  @override
  String get accountMismatchDownloadFailed => '파일로 내려받지 못했어요. 다시 시도해 주세요.';

  @override
  String get accountMismatchDownloadNone => '내려받을 수 있는 노트가 없어요.';

  @override
  String accountMismatchDownloadSkipped(int skipped, int total) {
    return '노트 $total개 중 $skipped개를 저장하지 못했어요.';
  }

  @override
  String get accountClearFailed => '이전 계정의 노트 사본을 지우지 못했어요. 다시 시도해 주세요.';

  @override
  String get unsentLogoutTitle => '보내지 못한 변경이 있어요';

  @override
  String unsentLogoutBody(int count) {
    return '보내지 못한 변경 $count개가 있어요. 로그아웃하면 이 변경이 사라져요.';
  }

  @override
  String get unsentLogoutBodyUnknown =>
      '보내지 못한 변경이 있는지 확인하지 못했어요. 로그아웃하면 사라질 수 있어요.';

  @override
  String get unsentLogoutConfirm => '버리고 로그아웃';

  @override
  String unsentDisconnectLine(int count) {
    return '보내지 못한 변경 $count개가 있어요.';
  }

  @override
  String get unsentDisconnectLineUnknown => '보내지 못한 변경이 있는지 확인하지 못했어요.';

  @override
  String get unsentDisconnectConfirm => '버리고 연결 해제';

  @override
  String get syncStateSaved => '저장됨';

  @override
  String get syncStatePending => '저장 대기';

  @override
  String get syncStateOffline => '오프라인 · 이 기기에 보관 중';

  @override
  String get syncBadgeOffline => '오프라인';

  @override
  String get syncStateSaving => '저장 중';

  @override
  String get syncStateReceiving => '최신 내용 받는 중';

  @override
  String get syncStateTwoVersions => '두 버전';

  @override
  String get syncStateNotSaved => '저장 안 됨';

  @override
  String syncIndicatorLabel(String state) {
    return '동기화 상태: $state. 자세히 보기';
  }

  @override
  String get syncDescSaved => '모든 변경이 Drive에 저장됐어요.';

  @override
  String get syncDescPending => '곧 Drive에 저장해요.';

  @override
  String get syncDescOffline => '오프라인이에요. 변경은 이 기기에 보관 중이고, 연결되면 저장해요.';

  @override
  String get syncDescSaving => 'Drive에 저장하는 중이에요.';

  @override
  String get syncDescReceiving => '다른 기기의 최신 내용을 받는 중이에요.';

  @override
  String get syncDescTwoVersions => '두 기기에서 고친 페이지가 있어요.';

  @override
  String get syncNow => '지금 동기화';

  @override
  String get syncErrorBody => '변경은 이 기기에 보관 중이에요. 다시 시도하거나 동기화 로그 내보내기를 해 주세요.';

  @override
  String get syncQuotaBody => 'Drive 저장 공간이 부족해요. 이 기기에 보관 중이에요.';

  @override
  String get syncManageDrive => 'Drive 공간 관리';

  @override
  String get syncOpenFailed => '페이지를 열지 못했어요.';

  @override
  String get syncReauthBanner => '로그인이 만료됐어요. 변경은 이 기기에 보관 중이에요.';

  @override
  String get close => '닫기';

  @override
  String get deletedBanner => '다른 기기에서 지운 노트예요.';

  @override
  String get deletedRevive => '다시 살리기';

  @override
  String get revivedSnack => '다른 기기에서 지운 노트에 보내지 않은 변경이 있어 되살렸어요.';

  @override
  String get newVersionBanner => '새 버전에서 만든 노트예요. 앱을 업데이트하면 편집할 수 있어요.';

  @override
  String get cannotOpenBody => '이 노트 파일을 읽을 수 없어요. 파일은 그대로 두었어요.';

  @override
  String get cannotOpenViewInDrive => 'Drive에서 보기';

  @override
  String get cannotOpenDownload => '파일로 내려받기';

  @override
  String get conflictBanner => '다른 기기에서도 고친 페이지예요. 고를 때까지는 읽기만 돼요.';

  @override
  String get conflictBannerDeleted =>
      '다른 기기에서 지운 페이지가 있어요. 고를 때까지 이 기기 버전을 보관해요.';

  @override
  String get conflictResolveAction => '해결하기';

  @override
  String get conflictReadOnlyBlocked => '읽기 전용 페이지예요';

  @override
  String conflictFound(int n) {
    return '$n페이지를 두 기기에서 고쳤어요. 고를 때까지 읽기만 돼요.';
  }

  @override
  String conflictFoundDeleted(int n) {
    return '$n페이지를 다른 기기에서 지웠어요. 고를 때까지 이 기기 버전을 보관해요.';
  }

  @override
  String get conflictPageSemantics => '읽기 전용, 두 기기에서 고친 페이지';

  @override
  String get conflictNotificationTitle => '두 기기에서 고친 페이지가 있어요';

  @override
  String get conflictNotificationChannel => '충돌';

  @override
  String get conflictSheetTitle => '두 기기에서 고친 페이지가 있어요';

  @override
  String conflictSheetProgress(int page, int i, int total) {
    return '$page페이지 · $i/$total';
  }

  @override
  String get conflictPrev => '이전 충돌 페이지';

  @override
  String get conflictNext => '다음 충돌 페이지';

  @override
  String get conflictQuestion => '어느 쪽을 남길까요?';

  @override
  String get conflictTagThis => '이 기기';

  @override
  String get conflictTagOther => '다른 기기';

  @override
  String get conflictMoreRecent => '더 최근';

  @override
  String conflictEditedAt(String device, String time) {
    return '$device · $time';
  }

  @override
  String get conflictKeepThis => '이 기기 버전';

  @override
  String get conflictKeepOther => '다른 기기 버전';

  @override
  String get conflictKeepBoth => '둘 다 남기기';

  @override
  String get conflictRecoverNote => '고르지 않은 버전은 30일 동안 버전 기록에서 되살릴 수 있어요.';

  @override
  String get conflictLater => '나중에 결정';

  @override
  String get conflictDeletedHere => '이 기기에서 지운 페이지';

  @override
  String get conflictDeletedOther => '다른 기기에서 지운 페이지';

  @override
  String get conflictRemovePage => '페이지 지우기';

  @override
  String get conflictKeepVersion => '이 버전 남기기';

  @override
  String get conflictRestAllThis => '나머지 모두 이 기기 버전';

  @override
  String get conflictRestAllOther => '나머지 모두 다른 기기 버전';

  @override
  String conflictRestAllConfirm(int n) {
    return '한 번 더 누르면 $n페이지에 적용돼요';
  }

  @override
  String conflictPreviewSemantics(String tag, int n) {
    return '$n페이지 $tag 버전';
  }

  @override
  String conflictResolvedBoth(int n) {
    return '$n페이지: 둘 다 남겼어요';
  }

  @override
  String conflictResolvedThis(int n) {
    return '$n페이지: 이 기기 버전을 남겼어요';
  }

  @override
  String conflictResolvedOther(int n) {
    return '$n페이지: 다른 기기 버전을 남겼어요';
  }

  @override
  String conflictResolvedRemove(int n) {
    return '$n페이지: 지웠어요';
  }

  @override
  String conflictResolvedKeep(int n) {
    return '$n페이지: 남겼어요';
  }

  @override
  String conflictResolvedAll(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n페이지를 정했어요',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolveFailed => '정하지 못했어요. 다시 시도해 주세요.';

  @override
  String get versionHistory => '버전 기록';

  @override
  String get versionHistoryEmpty => '아직 이전 버전이 없어요. 새로고침하면 다시 확인해요.';

  @override
  String get versionHistoryRefresh => '새로고침';

  @override
  String get versionRestoreChanged => '그사이 노트가 바뀌어서 복원하지 않았어요. 다시 눌러 주세요.';

  @override
  String get versionHistoryOffline => '연결되면 버전 기록을 볼 수 있어요.';

  @override
  String get versionHistoryFailed => '버전 기록을 불러오지 못했어요.';

  @override
  String get versionHistoryLoading => '버전 기록을 불러오는 중이에요';

  @override
  String get versionTagConflict => '충돌로 남긴 버전';

  @override
  String get versionTagBeforeRestore => '복원 전';

  @override
  String get versionPreviewUnavailable => '미리 볼 수 없어요';

  @override
  String get versionPreviewSemantics => '버전 미리보기';

  @override
  String get versionRestore => '이 버전으로 복원';

  @override
  String get versionRestoreConfirm => '한 번 더 누르면 이 버전으로 바뀌어요';

  @override
  String get versionRestoring => '복원하는 중이에요';

  @override
  String get versionRestored => '이 버전으로 되돌렸어요';

  @override
  String get versionRestoreFailed => '복원하지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get versionRestoreOffline => '연결되면 복원할 수 있어요.';

  @override
  String get versionRestoreNotSaved => '지금 상태를 Drive에 저장하지 못해서 복원하지 않았어요.';

  @override
  String get versionRestorePinFailed => '복원 전 버전을 표시하지 못해서 복원하지 않았어요.';

  @override
  String get versionRestoreUnreadable => '이 버전을 읽을 수 없어요.';
}
