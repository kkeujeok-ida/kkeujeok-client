# kkeujeok-client

Kkeujeok Android 앱 (Flutter). Android 10(API 29) 이상.

## 준비

- 이 레포는 **루트 `kkeujeok` 레포 안에** 클론한다. 테스트가 형제 폴더
  `../test/`의 공용 픽스처를 그대로 읽기 때문이다.

  ```
  kkeujeok/
    spec/
    test/              <- 공용 픽스처, `flutter test`가 그대로 읽는다
    kkeujeok-client/   <- 이 레포
  ```

- Flutter **3.47.7** (Dart 3.13.5), JDK 17 이상, Android SDK.

## 실행과 테스트

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=config/dev.json
flutter build apk --debug --dart-define-from-file=config/dev.json
```

`flutter test`는 `../test/`가 없거나, 이 클라이언트가 구현하지 않은 규칙의
픽스처가 있으면 건너뛰지 않고 실패한다.

## 계정별 설정 (`config/dev.json`)

계정별 값은 레포에 커밋하지 않는다. 예시 파일을 복사해서 값을 채운다.

```sh
cp config/dev.example.json config/dev.json
```

`config/dev.json`은 `.gitignore`에 들어 있다. 값이 비어 있어도 앱은
실행된다.

- `GOOGLE_SERVER_CLIENT_ID`: GCP 프로젝트의 **웹** OAuth 클라이언트 ID.
  Android의 Google 로그인(`google_sign_in` 7.x, Credential Manager)이
  `serverClientId`로 요구한다. 비어 있으면 로그인이 구성 오류로 실패한다.
- `PRIVACY_URL`: 웹 `/privacy` 주소(예: `https://<도메인>/privacy`). 비어 있으면
  설정의 개인정보처리방침 항목이 비활성화되고 이유를 안내한다.

## 문구(다국어)

문구는 `lib/l10n/app_{ko,en}.arb`에서만 온다. 고친 뒤 `flutter gen-l10n`을
실행하고 생성물(`lib/l10n/app_localizations*.dart`)도 커밋한다.

## 자기 GCP 프로젝트에 디버그 SHA-1 등록

프로덕션 OAuth 클라이언트에는 Play 앱 서명 키만 등록되어 있다. 디버그
빌드로 Google 로그인을 하려면 자기 GCP 프로젝트를 쓴다.

1. 디버그 키의 SHA-1을 확인한다.

   ```sh
   cd android
   ./gradlew signingReport
   ```

   또는

   ```sh
   keytool -list -v -alias androiddebugkey -storepass android -keypass android \
     -keystore ~/.android/debug.keystore
   ```

   (Windows: `%USERPROFILE%\.android\debug.keystore`)

2. [Google Cloud Console](https://console.cloud.google.com/)에서 자기
   프로젝트를 만들고 Google Drive API를 켠다.
3. OAuth 동의 화면을 만들고(External, Testing) 자기 계정을 테스트 사용자로
   넣는다.
4. 사용자 인증 정보 → OAuth 클라이언트 ID → **Android**를 만든다. 패키지
   이름은 `com.kkeujeok.app`, SHA-1은 1번 값이다.
5. 같은 프로젝트에 **웹 애플리케이션** OAuth 클라이언트를 하나 더 만들고 그
   ID를 `config/dev.json`의 `GOOGLE_SERVER_CLIENT_ID`에 넣는다.
6. 동의 화면의 범위에 `.../auth/drive.file`을 추가한다. 앱이 요청하는 권한은
   이것뿐이다.

키스토어와 `key.properties`는 커밋하지 않는다.

## 폴더

`lib/` 아래 레이어는 웹 클라이언트의 `src/`와 같다:
`model/ ops/ sync/ storage/ drive/ render/ ui/`.

## 라이선스

GPL-3.0
