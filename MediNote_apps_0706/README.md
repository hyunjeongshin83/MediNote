# MediNote — 안드로이드 · iOS 앱 코드

메디노트 웹앱(예방접종·복약 안내)을 **안드로이드**와 **iOS(애플)** 앱으로 감싼 코드입니다.
두 앱 모두 앱 안에 웹 화면(`index.html`)을 포함해, **인터넷 없이도 열립니다(오프라인)**.
기기 안에 데이터를 보관하는 **로컬 저장**도 켜져 있습니다.

## 추천 방식으로 만든 이유

- 이미 완성된 웹앱(HTML) 하나를 두 앱이 함께 사용합니다.
  → 화면을 고칠 때 **웹앱 한 곳만 고치면** 안드로이드·iOS·웹페이지가 모두 바뀝니다.
- 안드로이드·iOS를 각각 처음부터 다시 만드는 것보다, 유지가 훨씬 간단합니다.
- 같은 `index.html`은 **웹페이지로도 그대로** 열 수 있습니다.

## 폴더 구성

```
medinote_apps/
├─ shared/index.html         ← 웹앱 (웹페이지로도 사용)
├─ android/                  ← 안드로이드 앱 (Kotlin, WebView)
│  └─ app/src/main/
│     ├─ assets/index.html   ← 앱에 포함된 화면
│     ├─ java/.../MainActivity.kt
│     ├─ AndroidManifest.xml
│     ├─ res/values/strings.xml
│     └─ build.gradle
└─ ios/                      ← iOS 앱 (Swift, WKWebView)
   └─ MediNote/
      ├─ index.html          ← 앱에 포함된 화면
      ├─ MediNoteApp.swift
      └─ ContentView.swift
```

## 열어보는 방법 (개발 도구 필요)

- **안드로이드:** Android Studio로 `android/` 폴더를 엽니다. 실행하면 에뮬레이터/기기에서 앱이 뜹니다.
- **iOS(애플):** Xcode로 새 SwiftUI 프로젝트를 만들고, `MediNoteApp.swift`·`ContentView.swift`·`index.html`을 넣습니다.
  (iOS 앱 빌드는 Mac과 Xcode가 필요합니다.)
- **웹페이지:** `shared/index.html`을 인터넷 브라우저에서 바로 열면 됩니다.

## 나중에 확장할 부분 (코드에 주석으로 표시)

- 더 큰 로컬 데이터베이스가 필요하면, 안드로이드는 **Room**, iOS는 **Core Data/SQLite**를 붙일 수 있습니다.
- 완전 오프라인으로 쓰려면, `index.html`이 인터넷에서 불러오는 React·폰트 파일도
  앱 안에 함께 넣고 경로를 바꿔야 합니다. (지금은 도우미 등 일부 기능에 인터넷이 필요합니다.)

## 안내

- 본 앱은 개념검증 시제품이며, 화면의 접종·복약 정보는 예시 데이터입니다.
- 접종 정보는 판정이 아니라 안내와 상담 연결까지만 제공합니다.
