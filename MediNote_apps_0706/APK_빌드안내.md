# APK 빌드 현황 (2026-09-20)

**결론부터 — 지금은 APK 자동 빌드가 되지 않습니다.**

전에 이 문서는 "코드를 올리면 APK 가 자동으로 만들어진다" 고 적고 있었습니다.
사실이 아니었습니다. 설정 파일이 있다고 적힌 `.github/workflows/android-build.yml`
은 저장소에 **없습니다.** 안드로이드 코드 자체도 지금 상태로는 빌드가 실패합니다.
잘못된 안내를 그대로 두면 대표님이 Actions 탭에서 없는 것을 찾게 되므로 바로잡습니다.

## 지금 되는 것

- **웹앱** — `MediNote_app.html` 을 브라우저에서 엽니다. 배포도 이쪽입니다.
- **앱에 들어갈 화면** — `MediNote_apps_0706/*/index.html`.
  인터넷 없이도 로그인 화면까지 열립니다(2026-09-20 확인).
  React·Supabase·접속 설정이 파일 안에 들어가 있습니다.

## 자동 빌드를 켜려면 아래 넷이 필요합니다

```
① Gradle 래퍼        android/gradlew · gradle/wrapper/gradle-wrapper.jar 가 없습니다.
                     gradle-wrapper.properties 만 있어서 ./gradlew 가 실행되지 않습니다.

② 앱 아이콘          AndroidManifest.xml 이 @mipmap/ic_launcher 를 가리키는데
                     res/mipmap-* 폴더가 없습니다. 리소스 연결 단계에서 멈춥니다.

③ 건강 연동 의존성    HealthConnectManager.kt 가 androidx.health.connect.client 를
                     import 하는데 app/build.gradle 에 그 줄이 없습니다. 컴파일 오류입니다.
                     (이 파일은 MainActivity 에서 쓰이지 않는 설계 초안입니다.
                      건강 연동을 실제로 붙일 때 의존성과 함께 살리면 됩니다.)

④ 워크플로 파일       .github/workflows/android-build.yml
                     ①~③ 이 끝나야 의미가 있습니다. 먼저 만들면 빨간 실패만 쌓입니다.
```

① ~ ③ 은 안드로이드 SDK 와 Google Maven 저장소(`dl.google.com`)에 닿는 곳에서
한 번 빌드해 보며 맞춰야 합니다. 지금 작업 환경에서는 그 주소가 막혀 있어
의존성 판본을 확인할 수 없었고, **확인하지 못한 설정을 넣지 않았습니다.**
넣었다면 Actions 가 매번 빨갛게 실패했을 것입니다.

## 그때까지 아이폰·안드로이드에서 쓰는 법

웹앱 주소를 휴대폰 브라우저에서 열고 **홈 화면에 추가** 하면 앱처럼 씁니다.
아이콘·전체화면·푸시까지 동작합니다(`manifest.webmanifest`, `MediNote.sw.js`).
APK 는 "지인에게 파일로 건네주기" 와 "플레이스토어 등록" 에 필요합니다.

## 참고 — 플레이스토어 등록

자동 빌드로 만들어지는 것은 **테스트용(디버그) 빌드**입니다.
스토어 등록에는 본인 개발자 키로 서명한 릴리스 빌드가 따로 필요합니다.
