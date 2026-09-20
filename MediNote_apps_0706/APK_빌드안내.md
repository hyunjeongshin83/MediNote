# APK 빌드 현황 (2026-09-20 · 오후 갱신)

**막혀 있던 셋을 고치고 워크플로를 넣었습니다. 첫 실행 결과를 기다리는 중입니다.**

오전까지 이 문서는 "지금은 자동 빌드가 되지 않는다" 고 적고 있었습니다. 맞는 말이었고,
막힌 것이 넷이었습니다. 그 중 셋을 고쳤고 네 번째(워크플로)를 넣었습니다.

| | 오전 | 지금 |
|---|---|---|
| ① Gradle 래퍼 | `gradlew` · `gradle-wrapper.jar` 없음 | **필요 없게 했습니다** — Actions 가 8.9 를 박아 설치합니다 |
| ② 앱 아이콘 | `res/mipmap-*` 없음 | **만들었습니다** — 5개 밀도 · 둥근 아이콘 포함 |
| ③ 건강 연동 의존성 | `app/build.gradle` 에 없음 | **넣었습니다** — `connect-client:1.1.0-alpha07` |
| ④ 워크플로 | 없음 | **`.github/workflows/android-build.yml`** |

**아직 「된다」고 말하지 않습니다.** 이 작업 환경에서는 `dl.google.com`(구글 메이븐)과
`services.gradle.org` 가 막혀 있어, 의존성이 실제로 받아지는지 확인할 수 없었습니다.
**Actions 러너는 그 주소에 닿습니다** — 그래서 워크플로의 첫 실행이 곧 그 확인입니다.
빨갛게 뜨면 로그에 무엇이 안 받아졌는지 나오고, 그것을 보고 고칩니다.

## 지금 되는 것

- **웹앱** — `MediNote_app.html` 을 브라우저에서 엽니다. 배포도 이쪽입니다.
- **앱에 들어갈 화면** — `MediNote_apps_0706/*/index.html`.
  인터넷 없이도 로그인 화면까지 열립니다(2026-09-20 확인).
  React·Supabase·접속 설정이 파일 안에 들어가 있습니다.

## APK 를 받는 법

GitHub 저장소 → **Actions** 탭 → **「안드로이드 APK」** → 맨 위 실행 → 맨 아래
**Artifacts** 의 `medinote-debug-N` 을 내려받으면 그 안에 `.apk` 가 있습니다.
안드로이드 코드나 `MediNote_app.html` 이 바뀌면 저절로 한 번 돕니다.
손으로 돌리고 싶으면 같은 화면에서 **Run workflow** 를 누르시면 됩니다.

### 빌드가 하는 일

```
1  앱 화면이 웹앱과 같은지 본다   tools/build-packaged-app.py --check
   7월 사본이 두 달 넘게 웹앱과 달랐던 적이 있습니다 (issues #12).
   손으로 옮기면 또 벌어지므로 여기서 먼저 막습니다.
2  Java 17 · Gradle 8.9 설치
3  gradle assembleDebug
4  나온 APK 를 Artifacts 에 올린다 (30일 보관)
   실패하면 대신 build/reports 를 올린다 — 무엇이 막혔는지 보려고
```

### Gradle 래퍼를 왜 안 넣었나

`gradle-wrapper.jar` 는 저장소에 넣는 **바이너리**라 무엇이 들었는지 눈으로 볼 수
없습니다. 여기서는 Actions 가 Gradle 8.9 를 박아 설치하므로 래퍼가 필요 없습니다.
판본은 `gradle/wrapper/gradle-wrapper.properties` 와 같게 맞춰 두었습니다.

손 PC 에서 빌드하실 때는 Gradle 8.9 를 설치하고 `android/` 에서
`gradle assembleDebug` 를 쓰시면 됩니다.

## 그때까지 아이폰·안드로이드에서 쓰는 법

웹앱 주소를 휴대폰 브라우저에서 열고 **홈 화면에 추가** 하면 앱처럼 씁니다.
아이콘·전체화면·푸시까지 동작합니다(`manifest.webmanifest`, `MediNote.sw.js`).
APK 는 "지인에게 파일로 건네주기" 와 "플레이스토어 등록" 에 필요합니다.

## 참고 — 플레이스토어 등록

자동 빌드로 만들어지는 것은 **테스트용(디버그) 빌드**입니다.
스토어 등록에는 본인 개발자 키로 서명한 릴리스 빌드가 따로 필요합니다.
