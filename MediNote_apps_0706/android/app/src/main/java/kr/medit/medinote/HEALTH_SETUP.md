# 건강 데이터 연동 — 빌드/테스트 준비 안내

## 구조 (합법적 설계)
- 건강 센서 데이터(걸음·심박)는 '민감정보'입니다.
- 이 매니저(HealthConnectManager · HealthKitManager)는 데이터를 **서버로 보내지
  않고**, 기기 안에서 읽어 **로컬에서만 계산**하도록 설계했습니다.
- 사용자 동의는 OS 권한 화면으로 **별도** 수령합니다.
- 로그인(Google·카카오·네이버)과 건강 데이터는 **완전히 분리**되어 있습니다.

> ⚠️ **지금 앱 전체가 그렇다는 뜻은 아닙니다.**
> **Android** 는 2026-09-25 부터 화면에 연결돼 있습니다 (MN-14-2). MainActivity 의
> `window.Native` 다리 → 「건강기기 연결」 시트의 「건강 데이터 읽기 (Health Connect)」.
> 걸음 24시간 · 심박 6시간 · 수면 24시간을 읽어 보여 주고, 기기 localStorage
> (`medinote:hc:v1`)에만 둡니다. 이 경로는 서버로 보내지 않습니다.
> **iOS HealthKitManager 는 아직 연결돼 있지 않습니다.**
>
> 같은 시트의 **블루투스(BLE) 읽기**는 별개 경로입니다. 「읽은 값 클라우드에 저장」
> 단추를 누르면 값이 Supabase `measurements` 로 **올라갑니다.**

## 연동 원리
워치/밴드 → 폰의 건강 플랫폼(Health Connect / HealthKit) → (동의) → 앱이 로컬에서 읽음
- 앱은 워치와 직접 통신하지 않습니다. 폰의 건강 플랫폼에서 읽습니다.
- Apple Watch 데이터는 **아이폰 네이티브 앱의 HealthKit로만** 접근 가능합니다.
  (웹페이지·윈도우/안드로이드 PC에서는 접근 불가)

## Android — 남은 설정 (APK 테스트 직전)
1. app/build.gradle 의 dependencies 에 추가:
   implementation "androidx.health.connect:connect-client:1.1.0-alpha07"
2. AndroidManifest.xml 에 권한 추가:
   <uses-permission android:name="android.permission.health.READ_STEPS"/>
   <uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
   <uses-permission android:name="android.permission.health.READ_SLEEP"/>
   (1·2 는 들어 있습니다. 「왜 읽는지」 화면용 intent-filter · activity-alias 도 들어 있습니다.)
3. 테스트 기기에 'Health Connect' 앱 설치(최신 안드로이드는 내장).
4. 화면 연결은 끝났습니다 — 앱의 「건강기기 연결」 시트에서 「건강 데이터 읽기」.

## iOS — 남은 설정 (빌드 직전)
1. Xcode → Signing & Capabilities → **HealthKit** 추가.
2. Info.plist 에 사용 목적 문구 추가:
   NSHealthShareUsageDescription = "복약·접종 안내를 돕기 위해 건강 데이터를 읽습니다. 데이터는 기기 안에 있습니다."
3. HealthKitManager 를 화면의 '연결' 버튼에 연결하면 바로 테스트 가능.
4. iOS 앱 빌드는 Mac + Xcode 가 필요합니다.

## 프로토타입 안내
- 실제 개인 건강정보 연결 전에는 예시 데이터로 흐름만 시연하세요.
- 실제 연동은 별도 동의 화면과 법적 검토를 갖춘 뒤 진행합니다.
