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
  String get library => '노트';

  @override
  String get viewLabel => '보기 방식';

  @override
  String get viewList => '리스트';

  @override
  String get viewGrid => '그리드';

  @override
  String get viewSmall => '작은';

  @override
  String get viewStandard => '표준';

  @override
  String get viewLarge => '큰';

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
  String get theme => '테마';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get themeAllDark => '올 다크';

  @override
  String get leftHanded => '왼손잡이';

  @override
  String get pressureCurve => '필압 커브';

  @override
  String get pressureCurveSoft => '부드럽게';

  @override
  String get pressureCurveNormal => '보통';

  @override
  String get pressureCurveFirm => '단단하게';

  @override
  String get pressureCurveX1 => '제어점 1 가로 (x1)';

  @override
  String get pressureCurveY1 => '제어점 1 세로 (y1)';

  @override
  String get pressureCurveX2 => '제어점 2 가로 (x2)';

  @override
  String get pressureCurveY2 => '제어점 2 세로 (y2)';

  @override
  String get pressureCurvePad => '시험 획 영역. 펜으로 그어 필압 커브를 확인해요';

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
  String get colorBlue => '파랑';

  @override
  String get colorYellow => '노랑';

  @override
  String get colorCustom => '사용자 지정';

  @override
  String highlighterSlotLabel(String color, String width) {
    return '형광펜, $color, 두께 $width';
  }

  @override
  String get addPenSlot => '펜 슬롯 추가';

  @override
  String get deletePenSlot => '도구 삭제';

  @override
  String get penSlotDeleted => '도구를 지웠어요';

  @override
  String get moveSlotEarlier => '앞으로 이동';

  @override
  String get moveSlotLater => '뒤로 이동';

  @override
  String get scrollSlotsBack => '앞쪽 슬롯 보기';

  @override
  String get scrollSlotsForward => '뒤쪽 슬롯 보기';

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
  String get penDiagTitle => '펜 입력 진단';

  @override
  String get penDiagHint => '아래 영역에 펜을 대거나, 펜 버튼을 누르거나, 지우개 끝으로 그어 보세요.';

  @override
  String get penDiagEmpty => '아직 이벤트가 없어요';

  @override
  String get penDiagCopy => '이벤트 복사';

  @override
  String get penDiagCopied => '복사했어요';

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
  String get viewModeVertical => '세로 연속';

  @override
  String get viewModeHorizontal => '가로 스크롤';

  @override
  String get viewModeTwoPage => '두 페이지';

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

  @override
  String get noteDelete => '삭제';

  @override
  String get noteDeleteBody => '노트를 지울까요? 휴지통으로 옮겨져요. 휴지통에서 복구할 수 있어요.';

  @override
  String get noteDeleteConfirm => '지우기';

  @override
  String get ratioLock => '비율 잠금';

  @override
  String get scaleUp => '크게';

  @override
  String get scaleDown => '작게';

  @override
  String get rotate90 => '90° 회전';

  @override
  String get strokeColor => '색';

  @override
  String get strokeWidth => '두께';

  @override
  String get copy => '복사';

  @override
  String get cut => '잘라내기';

  @override
  String get delete => '삭제';

  @override
  String get paste => '붙여넣기';

  @override
  String get selectAll => '전체 선택';

  @override
  String get lassoTool => '올가미';

  @override
  String get textTool => '텍스트';

  @override
  String get eraserTool => '지우개';

  @override
  String get eraserOptionsTitle => '지우개 설정';

  @override
  String get eraserModeStroke => '획 단위';

  @override
  String get eraserModePartial => '부분';

  @override
  String get eraserReturnToPen => '다 지우면 펜으로 돌아가기';

  @override
  String get eraserAnnounceStroke => '획 단위 지우기';

  @override
  String get eraserAnnouncePartial => '부분 지우기';

  @override
  String get eraseNotApplied => '지우지 못했어요.';

  @override
  String get imageTool => '이미지';

  @override
  String get imageFromGallery => '갤러리';

  @override
  String get imageFromCamera => '카메라';

  @override
  String get imageTooLarge => '10MB보다 큰 이미지는 넣을 수 없어요.';

  @override
  String get imageUnsupported => '이 형식의 이미지는 넣을 수 없어요. JPEG, PNG, WebP만 가능해요.';

  @override
  String get imageConvertFailed => '이미지를 변환하지 못해서 넣을 수 없어요.';

  @override
  String get imageConverted => 'JPEG로 변환해서 넣었어요.';

  @override
  String get imageStoreFailed => '이미지를 저장하지 못했어요.';

  @override
  String get imagePermissionTitle => '권한이 필요해요';

  @override
  String get imagePermissionReason =>
      '사진을 넣으려면 카메라나 사진 접근 권한이 필요해요. 설정에서 허용해 주세요.';

  @override
  String get openSettings => '설정 열기';

  @override
  String get imageSemantics => '이미지';

  @override
  String get imagePendingSemantics => '저장 대기 중';

  @override
  String get imageDownloading => '이미지 받는 중';

  @override
  String get imageDownloadFailed => '받기 실패';

  @override
  String get imageRetry => '다시 시도';

  @override
  String get fontSize => '글자 크기';

  @override
  String fontSizeValue(String size) {
    return '글자 크기 $size';
  }

  @override
  String get textColor => '글자 색';

  @override
  String get bold => '굵게';

  @override
  String get italic => '기울임';

  @override
  String get on => '켜짐';

  @override
  String get off => '꺼짐';

  @override
  String selectedCount(int n) {
    return '$n개 선택됨';
  }

  @override
  String get colorDarkGray => '진회색';

  @override
  String get colorRed => '빨강';

  @override
  String get colorOrange => '주황';

  @override
  String get colorGreen => '초록';

  @override
  String get colorTeal => '청록';

  @override
  String get colorIndigo => '남색';

  @override
  String get colorPurple => '보라';

  @override
  String get colorPink => '분홍';

  @override
  String get colorBrown => '갈색';

  @override
  String get colorSky => '하늘';

  @override
  String get colorLavender => '연보라';

  @override
  String get toolPen => '펜';

  @override
  String get toolHighlighter => '형광펜';

  @override
  String get recentColors => '최근';

  @override
  String get widthDecrease => '두께 줄이기';

  @override
  String get widthIncrease => '두께 늘리기';

  @override
  String get colorPickerApply => '적용';

  @override
  String get colorPickerCancel => '취소';

  @override
  String get colorHue => '색조';

  @override
  String get colorSaturation => '채도';

  @override
  String get colorBrightness => '밝기';

  @override
  String strokeWidthValue(String v) {
    return '두께 $v';
  }

  @override
  String customColorSlotLabel(String hex) {
    return '사용자 지정 색 $hex';
  }

  @override
  String get visibleToolsTitle => '한 번에 볼 도구 수';

  @override
  String get visibleToolsLess => '도구 수 줄이기';

  @override
  String get visibleToolsMore => '도구 수 늘리기';

  @override
  String get palettePenTitle => '펜·형광펜 팔레트';

  @override
  String get paletteAdd => '색 추가';

  @override
  String get paletteReset => '기본값으로';

  @override
  String get paletteFull => '팔레트는 최대 18색이에요.';

  @override
  String paletteEarlier(String color) {
    return '$color 앞으로 이동';
  }

  @override
  String paletteLater(String color) {
    return '$color 뒤로 이동';
  }

  @override
  String paletteRemove(String color) {
    return '$color 삭제';
  }

  @override
  String get penOnlyTitle => '펜으로만 필기';

  @override
  String get penOnlyAuto => '자동';

  @override
  String get penOnlyOn => '켜기';

  @override
  String get penOnlyOff => '끄기';

  @override
  String get toolbarMove => '툴바 위치 바꾸기';

  @override
  String get dockTop => '상단';

  @override
  String get dockLeft => '왼쪽';

  @override
  String get dockRight => '오른쪽';

  @override
  String get dockBottom => '하단';

  @override
  String toolbarDocked(String place) {
    return '툴바를 $place에 붙였어요';
  }

  @override
  String noteChip(String title, int n, int total) {
    return '$title · $n/$total';
  }

  @override
  String noteBackTo(String title) {
    return '‘$title’로 돌아가기';
  }

  @override
  String noteOpened(String title) {
    return '‘$title’ 열림';
  }

  @override
  String get noteBackUndo => '돌아가기';

  @override
  String get pageOverviewOpen => '페이지';

  @override
  String get pageOverviewTitle => '페이지';

  @override
  String get pageAdd => '페이지 추가';

  @override
  String get pageSelect => '선택';

  @override
  String get pageMenu => '페이지 메뉴';

  @override
  String get pageCurrent => '현재';

  @override
  String get pageConflictBadge => '충돌';

  @override
  String pageOutOfBoundsBadge(int n) {
    return '페이지 밖 요소 $n개';
  }

  @override
  String get pageLandscape => '가로';

  @override
  String get pagePortrait => '세로';

  @override
  String pageAdded(int n) {
    return '$n페이지를 추가했어요';
  }

  @override
  String pageDeleted(int n) {
    return '$n페이지를 지웠어요';
  }

  @override
  String pageDuplicated(int n) {
    return '$n페이지를 복제했어요';
  }

  @override
  String get pageUndo => '되돌리기';

  @override
  String get pageDeleteContentConfirm => '내용이 있는 페이지가 있습니다. 정말 삭제하시겠습니까?';

  @override
  String get pageDuplicate => '복제';

  @override
  String get pageDelete => '삭제';

  @override
  String get pagePullMore => '계속 당기면 페이지 추가';

  @override
  String get pagePullRelease => '놓으면 페이지 추가';

  @override
  String pageSelected(int count) {
    return '$count장 선택';
  }

  @override
  String get pageSelectDone => '완료';

  @override
  String get pageMoveEarlier => '앞으로';

  @override
  String get pageMoveLater => '뒤로';

  @override
  String get pageMoveFirst => '맨 앞으로';

  @override
  String get pageMoveLast => '맨 뒤로';

  @override
  String pageMoved(int n, int pos) {
    return '$n페이지를 $pos번째로 옮겼어요';
  }

  @override
  String pagesMoved(int count) {
    return '$count장을 옮겼어요';
  }

  @override
  String pagesDeleted(int count) {
    return '$count장을 지웠어요';
  }

  @override
  String pagesDuplicated(int count) {
    return '$count장을 복제했어요';
  }

  @override
  String get pageBackgroundShort => '배경';

  @override
  String get pageChangeBackground => '배경 바꾸기';

  @override
  String get pageToLandscape => '가로로 바꾸기';

  @override
  String get pageToPortrait => '세로로 바꾸기';

  @override
  String pageBackgroundChanged(int n) {
    return '$n페이지 배경을 바꿨어요';
  }

  @override
  String pagesBackgroundChanged(int count) {
    return '$count장의 배경을 바꿨어요';
  }

  @override
  String pageTurnedLandscape(int n) {
    return '$n페이지를 가로로 바꿨어요';
  }

  @override
  String pageTurnedPortrait(int n) {
    return '$n페이지를 세로로 바꿨어요';
  }

  @override
  String get allNotes => '모든 노트';

  @override
  String get folderAdd => '새 폴더';

  @override
  String folderMenu(String name) {
    return '$name 메뉴';
  }

  @override
  String get folderNewSub => '새 하위 폴더';

  @override
  String get folderRename => '이름 변경';

  @override
  String get folderMove => '이동';

  @override
  String get folderDelete => '삭제';

  @override
  String get folderNameLabel => '폴더 이름';

  @override
  String get folderNameTooLong => '폴더 이름은 100자까지예요.';

  @override
  String get folderSave => '저장';

  @override
  String get searchHint => '제목 검색';

  @override
  String get searchClear => '검색어 지우기';

  @override
  String searchNoResults(String q) {
    return '‘$q’와 맞는 노트가 없어요';
  }

  @override
  String searchResultCount(int n) {
    return '노트 $n개';
  }

  @override
  String get folderEmpty => '이 폴더에 노트가 없어요';

  @override
  String folderDeleteBody(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '이 폴더와 안의 노트 $n개를 앱 휴지통으로 옮겨요.',
      zero: '이 폴더를 앱 휴지통으로 옮겨요.',
    );
    return '$_temp0';
  }

  @override
  String get folderDeleteConfirm => '지우기';

  @override
  String get folderTopLevel => '홈';

  @override
  String get folderColor => '색상';

  @override
  String get folderColorDefault => '기본';

  @override
  String folderColorOption(int n) {
    return '색상 $n';
  }

  @override
  String folderMoveTitle(String name) {
    return '\"$name\" 옮길 곳';
  }

  @override
  String folderMoved(String name) {
    return '\"$name\" 폴더를 옮겼어요';
  }

  @override
  String get folderFailed => '폴더를 바꾸지 못했어요.';

  @override
  String get noteRename => '이름 변경';

  @override
  String get noteMove => '이동';

  @override
  String noteMoveTitle(String name) {
    return '\"$name\" 옮길 곳';
  }

  @override
  String noteMoved(String name) {
    return '\"$name\" 폴더로 옮겼어요';
  }

  @override
  String get noteTitleTooLong => '노트 제목은 100자까지예요.';

  @override
  String get noteActionFailed => '노트를 바꾸지 못했어요.';

  @override
  String get noteCover => '표지';

  @override
  String get noteChangeCover => '표지 변경';

  @override
  String get coverNone => '표지 없음';

  @override
  String coverOptionSelected(String name) {
    return '표지, $name, 선택됨';
  }

  @override
  String coverOptionUnselected(String name) {
    return '표지, $name';
  }

  @override
  String get exportMenu => '내보내기';

  @override
  String get exportTitle => 'PDF 내보내기';

  @override
  String get exportRangeAll => '전체';

  @override
  String get exportRangeCurrent => '현재 페이지';

  @override
  String get exportRangeCustom => '페이지 범위';

  @override
  String get exportRangeLabel => '페이지, 예: 3-7';

  @override
  String get exportErrEmpty => '내보낼 페이지를 입력해 주세요.';

  @override
  String get exportErrFormat => '페이지 번호나 3-7처럼 범위로 입력해 주세요.';

  @override
  String get exportErrReversed => '시작 페이지가 끝 페이지보다 뒤에 있어요.';

  @override
  String exportErrOutOfRange(int count) {
    return '페이지는 1부터 $count 사이여야 해요.';
  }

  @override
  String get exportStart => '내보내기';

  @override
  String exportProgress(int done, int total) {
    return 'PDF 만드는 중 · $done/$total페이지';
  }

  @override
  String get exportFailed => 'PDF를 만들지 못했어요.';

  @override
  String get exportPdfMissing => 'PDF 원본을 아직 받지 못해 내보낼 수 없어요.';

  @override
  String get exportAssetMissing =>
      '아직 이 기기에 없는 이미지가 있어요. 인터넷에 연결해 이미지를 받은 뒤 다시 시도해 주세요.';

  @override
  String get folderParentCard => '상위 폴더로';

  @override
  String get folderOpenHint => '폴더를 열어요';

  @override
  String get folderDropHint => '길게 눌러 다른 폴더 위로 끌면 옮겨요';

  @override
  String get selectCancel => '선택 취소';

  @override
  String get selectMove => '선택한 노트 이동';

  @override
  String get selectDelete => '선택한 노트 삭제';

  @override
  String notesDeleteBody(int n) {
    return '노트 $n개를 지울까요? 휴지통으로 옮겨져요. 휴지통에서 복구할 수 있어요.';
  }

  @override
  String notesMoveTitle(int n) {
    return '노트 $n개 옮길 곳';
  }

  @override
  String notesMoved(int n, String name) {
    return '노트 $n개를 \"$name\" 폴더로 옮겼어요';
  }

  @override
  String get searchOpen => '검색';

  @override
  String get pdfImport => 'PDF 가져오기';

  @override
  String pdfImportProgress(int done, int total) {
    return 'PDF 가져오는 중 · $done/$total페이지';
  }

  @override
  String get pdfErrTooLarge => '100MB보다 큰 PDF는 가져올 수 없어요.';

  @override
  String get pdfErrTooManyPages => '500페이지보다 긴 PDF는 가져올 수 없어요.';

  @override
  String get pdfErrEncrypted => '암호가 걸린 PDF는 가져올 수 없어요.';

  @override
  String get pdfErrUnreadable => '이 파일을 읽을 수 없어요.';

  @override
  String get pdfImportSaveFailed => 'PDF를 노트로 저장하지 못했어요.';

  @override
  String get pdfDownloading => 'PDF 받는 중';

  @override
  String get pdfDownloadFailed => 'PDF를 받지 못했어요';

  @override
  String get pdfPageSemantics => 'PDF 페이지';

  @override
  String get helpTitle => '도움말·제스처';

  @override
  String get helpGesturesHeader => '제스처';

  @override
  String get helpOneFinger => '손가락 한 개';

  @override
  String get helpOneFingerBody =>
      '펜으로만 필기가 꺼져 있으면 써요. 켜져 있으면 쪽이 여러 개인 노트를 스크롤하기만 해요.';

  @override
  String get helpTwoFingers => '손가락 두 개';

  @override
  String get helpTwoFingersBody => '모으거나 벌려서 확대·축소하고, 끌어서 화면을 옮겨요.';

  @override
  String get helpThreeFingers => '손가락 세 개';

  @override
  String get helpThreeFingersBody => '옆으로 쓸어서 이전·다음 노트로 가요.';

  @override
  String get helpPenButton => '펜 버튼·펜 뒤쪽';

  @override
  String get helpPenButtonBody => '버튼을 누른 채 쓰거나 펜을 뒤집으면 지워요.';

  @override
  String get helpPenOnlyHeader => '펜으로만 필기';

  @override
  String get helpPenOnlyBody =>
      '자동: 이 기기에서 펜이 한 번 감지되면 손가락으로는 쓰지 않아요. 켜기: 손가락으로 쓰지 않아요. 끄기: 손가락으로도 써요. 손가락으로 확대·축소와 화면 이동은 언제나 돼요. 설정에서 바꿀 수 있어요.';

  @override
  String get helpKeysHeader => '외장 키보드';

  @override
  String get helpKeyTools =>
      'P, H, L, E, T: 펜, 형광펜, 올가미, 지우개, 텍스트. 1~9: 그 번호의 펜.';

  @override
  String get helpKeyUndo => 'Ctrl+Z: 실행 취소. Ctrl+Shift+Z 또는 Ctrl+Y: 다시 실행.';

  @override
  String get helpKeyArrows => '방향키: 화면 이동.';

  @override
  String get hintFirstNote => '+로 첫 노트를 만들어 보세요';

  @override
  String get hintPenEdit => '선택한 펜을 한 번 더 누르면 색과 두께를 바꿀 수 있어요';

  @override
  String get trash => '휴지통';

  @override
  String get trashEmpty => '휴지통이 비어 있어요.';

  @override
  String get trashNoteBanner => '휴지통의 노트예요. 복구하면 다시 쓸 수 있어요.';

  @override
  String get trashRestore => '복구';

  @override
  String get trashPurge => '영구 삭제';

  @override
  String get trashPurgeConfirm => '한 번 더 누르면 영구 삭제돼요';

  @override
  String get trashEmptyAction => '휴지통 비우기';

  @override
  String get trashEmptyConfirm => '한 번 더 누르면 모두 영구 삭제돼요';

  @override
  String get trashRestored => '복구했어요';

  @override
  String get trashRestoredRoot => '원래 폴더가 없어서 최상위로 복구했어요';

  @override
  String get trashGone => '이미 없어진 항목이에요.';

  @override
  String get trashFailed => '처리하지 못했어요. 다시 시도해 주세요.';

  @override
  String trashNotes(int n) {
    return '노트 $n개';
  }

  @override
  String get trashKindNote => '노트';

  @override
  String get trashKindFolder => '폴더';

  @override
  String trashItemSemantics(String name, String kind, String date) {
    return '$name, $kind, $date에 지움';
  }

  @override
  String trashItemMenu(String name) {
    return '$name 메뉴';
  }

  @override
  String get trashCannotOpen => '열 수 없음';

  @override
  String noteDeleted(String title) {
    return '\"$title\" 노트를 휴지통으로 옮겼어요.';
  }

  @override
  String notesDeleted(int n) {
    return '노트 $n개를 휴지통으로 옮겼어요.';
  }

  @override
  String folderDeleted(String name) {
    return '\"$name\" 폴더를 휴지통으로 옮겼어요.';
  }

  @override
  String itemsDeleteBody(int n) {
    return '$n개 항목을 지울까요? 폴더는 안의 노트와 함께 휴지통으로 옮겨져요. 휴지통에서 복구할 수 있어요.';
  }

  @override
  String itemsMoveTitle(int n) {
    return '항목 $n개 옮길 곳';
  }

  @override
  String itemsMoved(int n, String name) {
    return '항목 $n개를 \"$name\" 폴더로 옮겼어요';
  }

  @override
  String itemsDeleted(int n) {
    return '항목 $n개를 휴지통으로 옮겼어요.';
  }
}
