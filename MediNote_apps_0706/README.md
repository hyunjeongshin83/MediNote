# MediNote — 안드로이드 · iOS 앱 코드 (MediNote_apps_0706)

메디노트 웹앱(예방접종·복약 안내)을 **안드로이드**와 **iOS(애플)** 앱으로 감싼 코드입니다.
두 앱 모두 앱 안에 웹 화면(`index.html`)을 포함해, **인터넷 없이도 열립니다(오프라인)**.
건강 데이터(걸음·심박)는 기기 안에서만 읽어 **로컬에서 계산**하며, 서버로 보내지 않습니다.

## 추천 방식으로 만든 이유

- 이미 완성된 웹앱(HTML) 하나를 두 앱이 함께 사용합니다.
  → 화면을 고칠 때 **웹앱 한 곳만 고치면** 안드로이드·iOS·웹페이지가 모두 바뀝니다.
- 같은 `shared/index.html`은 **웹페이지로도 그대로** 열 수 있습니다.

## 폴더 구성

이 폴더(`MediNote_apps_0706`)의 구성입니다.

```
MediNote_apps_0706/
├─ android/                   ← 안드로이드 앱 (Kotlin, WebView)
│  ├─ app/
│  │  ├─ src/main/
│  │  │  ├─ assets/index.html          ← 앱에 포함된 화면
│  │  │  ├─ java/kr/medit/medinote/
│  │  │  │  ├─ MainActivity.kt          ← 앱 진입점 (WebView)
│  │  │  │  ├─ HealthConnectManager.kt  ← 건강 데이터 로컬 연동
│  │  │  │  └─ HEALTH_SETUP.md          ← 건강 연동 설정 안내
│  │  │  ├─ AndroidManifest.xml
│  │  │  └─ res/values/strings.xml
│  │  └─ build.gradle
│  ├─ gradle/wrapper/gradle-wrapper.properties
│  ├─ build.gradle
│  ├─ gradle.properties
│  └─ settings.gradle
├─ ios/MediNote/              ← iOS 앱 (Swift, WKWebView)
│  ├─ index.html              ← 앱에 포함된 화면
│  ├─ MediNoteApp.swift       ← 앱 진입점
│  ├─ ContentView.swift       ← WebView 화면
│  └─ HealthKitManager.swift  ← 건강 데이터 로컬 연동
├─ shared/index.html          ← 웹앱 (웹페이지로도 사용)
├─ APK_빌드안내.md            ← APK 자동 빌드 사용법
└─ README.md                  ← 이 문서
```

> APK 자동 빌드 설정(`android-build.yml`)은 저장소 **최상위**의
> `.github/workflows/` 폴더에 있습니다. (이 폴더 안이 아니라 저장소 맨 위)
> 워크플로는 `working-directory: MediNote_apps_0706/android` 로 이 폴더의 코드를 빌드합니다.

## 열어보는 방법

- **APK 자동 빌드:** 코드를 저장소에 올리면 GitHub가 APK를 자동으로 만듭니다.
  자세한 방법은 `APK_빌드안내.md` 참고. (저장소 상단 Actions 탭 → 결과 APK 내려받기)
- **안드로이드:** Android Studio로 `android/` 폴더를 열어 실행할 수도 있습니다.
- **iOS(애플):** Xcode로 `ios/MediNote/` 파일들을 넣어 빌드합니다. (Mac + Xcode 필요)
- **웹페이지:** `shared/index.html`을 인터넷 브라우저에서 바로 엽니다.

## 건강 데이터 연동 (합법적 설계)

- 건강 센서 데이터(걸음·심박)는 개인정보보호법상 **민감정보**입니다.
- 앱은 데이터를 **서버로 보내지 않고**, 기기 안(Health Connect / HealthKit)에서 읽어
  **로컬에서만 계산**합니다. 사용자 동의는 OS 권한 화면으로 **별도** 수령합니다.
- 로그인(Google·카카오·네이버)과 건강 데이터는 **완전히 분리**되어 있습니다.
- 남은 설정과 연동 원리는 `android/app/src/main/java/kr/medit/medinote/HEALTH_SETUP.md` 참고.
- ※ Apple Watch 데이터는 아이폰 네이티브 앱의 HealthKit로만 접근 가능합니다.
  (웹페이지·윈도우/안드로이드 PC에서는 접근 불가)

## 안내

- 본 앱은 개념검증 시제품이며, 화면의 접종·복약 정보는 예시 데이터입니다.
- 접종 정보는 판정이 아니라 안내와 상담 연결까지만 제공합니다.
- 실제 개인 건강정보 연결 전에는 예시 데이터로 흐름만 시연하고,
  실제 연동은 별도 동의 화면과 법적 검토를 갖춘 뒤 진행합니다.
