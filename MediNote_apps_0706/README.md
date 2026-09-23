# MediNote — 안드로이드 · iOS 앱 코드 (MediNote_apps_0706)

메디노트 웹앱(예방접종·복약 안내)을 **안드로이드**와 **iOS(애플)** 앱으로 감싼 코드입니다.
두 앱 모두 앱 안에 웹 화면(`index.html`)을 포함해, **인터넷 없이도 열립니다(오프라인)**.
건강 데이터(걸음·심박)는 기기 안에서만 읽어 **로컬에서 계산**하며, 서버로 보내지 않습니다.

## 추천 방식으로 만든 이유

- 이미 완성된 웹앱(HTML) 하나를 두 앱이 함께 사용합니다.
  → 화면을 고칠 곳은 저장소 맨 위의 **`MediNote_app.html` 한 곳**입니다.
- 같은 `shared/index.html`은 **웹페이지로도 그대로** 열 수 있습니다.

### 화면을 고친 뒤에는 반드시

```
python3 tools/build-packaged-app.py
```

앱 안의 `index.html` 세 벌은 이 명령으로 **다시 만들어집니다.** 손으로 복사하지 마세요.

> 2026-07 부터 2026-09 까지 이 세 벌이 웹앱과 따로 놀았습니다.
> 앱 화면에는 로그인도 Supabase 연결도 없었고, React 를 인터넷에서 받고 있어
> **비행기 모드에서는 빈 화면**이었습니다. 지금은 React·Supabase·설정이
> 파일 안에 들어가 있어 인터넷 없이도 로그인 화면까지 열립니다.
> 갈라졌는지만 보려면 `python3 tools/build-packaged-app.py --check`.

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
├─ APK_빌드안내.md            ← APK 빌드 현황
└─ README.md                  ← 이 문서
```

`index.html` 세 곳과 그 옆의 아이콘·manifest 는 **만들어지는 파일**입니다.
직접 고치지 마세요 — `tools/build-packaged-app.py` 를 다시 돌리면 지워집니다.

> **APK 자동 빌드는 아직 설정돼 있지 않습니다.** 저장소에 `.github/` 폴더가 없습니다.
> 무엇이 더 필요한지는 `APK_빌드안내.md` 에 적어 두었습니다.

## 열어보는 방법

- **웹페이지:** `shared/index.html` 을 브라우저에서 바로 엽니다. **지금 바로 됩니다.**
- **안드로이드:** Android Studio 로 `android/` 폴더를 엽니다.
  다만 지금 이대로는 빌드가 **실패합니다** — 빠진 것이 `APK_빌드안내.md` 에 적혀 있습니다.
- **iOS(애플):** Xcode 로 `ios/MediNote/` 파일들을 넣어 빌드합니다. (Mac + Xcode 필요)
  `index.html` 과 그 옆의 아이콘·manifest 를 **모두** Bundle 에 넣으세요.
  하위 폴더가 없으므로 Xcode 에서 폴더 구조를 신경 쓸 일은 없습니다.

## 설치형 앱(APK · iOS)에서 지금 안 되는 것 (2026-09-24 확인 · #20)

두 앱은 `index.html` 을 **`file://` 로 WebView 에 띄웁니다.** 화면은 웹앱과 같지만(빌드가 매번 맞춥니다),
아래 세 기능은 웹앱(https · Android Chrome)에서만 되고 **설치형 앱에서는 안내문만 뜹니다.**

| 기능 | 웹앱 (https, Android Chrome) | Android APK (WebView) | iOS (WKWebView) | 안 되는 까닭 |
|---|---|---|---|---|
| 블루투스 건강기기 읽기 | 됨 | 안 됨 | 안 됨 | `navigator.bluetooth` 가 WebView·WKWebView 에 없음 |
| Google 로그인 | 됨 | 안 됨 | 안 됨 | 화면이 `file://` 이라 OAuth 가 돌아올 주소가 없음 (코드가 미리 막아 둠) |
| 푸시 알림 | Chrome 에서 됨 | 안 됨 | 안 됨 | `file://` 에서는 서비스워커 등록 불가 (#16) |
| 아이디·비밀번호 로그인 · 클라우드 저장 | 됨 | 됨 | 됨 | fetch 는 `file://` 에서도 나감 |

그래서 설치형 앱에서 「블루투스 기기 연결」을 누르면 **「Android Chrome 에서 열어 주세요」** 가 뜹니다.
연구 참여자에게 APK 를 나눠 줄 때 이 점을 먼저 알려야 합니다.

길은 두 가지이고, 어느 쪽인지는 결정이 필요합니다 (#20).
- **Android** — WebView 대신 **TWA(Trusted Web Activity)** 로 감싸면 Chrome 이 실행하므로 세 기능이 웹앱과 같아집니다.
- **iOS** — 같은 방법이 없습니다. CoreBluetooth · HealthKit · 네이티브 로그인 브리지를 따로 만들어야 합니다.

## 건강 데이터 연동 (합법적 설계)

- 건강 센서 데이터(걸음·심박)는 개인정보보호법상 **민감정보**입니다.
- `HealthConnectManager` · `HealthKitManager` 는 데이터를 **서버로 보내지 않고**,
  기기 안(Health Connect / HealthKit)에서 읽어 **로컬에서만 계산**하도록 짰습니다.
  사용자 동의는 OS 권한 화면으로 **별도** 수령합니다.
- **다만 이 두 매니저는 아직 화면에 연결돼 있지 않습니다.** 지금 실제로 도는 건강
  기능은 웹 화면의 블루투스 읽기이고, 거기에는 클라우드 저장 단추가 있습니다.
  자세한 것은 `android/.../HEALTH_SETUP.md` 를 보세요.
- 로그인(Google·카카오·네이버)과 건강 데이터는 **완전히 분리**되어 있습니다.
- 남은 설정과 연동 원리는 `android/app/src/main/java/kr/medit/medinote/HEALTH_SETUP.md` 참고.
- ※ Apple Watch 데이터는 아이폰 네이티브 앱의 HealthKit로만 접근 가능합니다.
  (웹페이지·윈도우/안드로이드 PC에서는 접근 불가)

## 안내

- 본 앱은 개념검증 시제품이며, 화면의 접종·복약 정보는 예시 데이터입니다.
- 접종 정보는 판정이 아니라 안내와 상담 연결까지만 제공합니다.
- 실제 개인 건강정보 연결 전에는 예시 데이터로 흐름만 시연하고,
  실제 연동은 별도 동의 화면과 법적 검토를 갖춘 뒤 진행합니다.
