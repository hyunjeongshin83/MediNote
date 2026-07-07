# iOS(애플) 앱 빌드·설치 안내

안드로이드와 달리, iOS는 **무료 자동 빌드(APK 같은)가 없습니다.**
아이폰에 앱을 올리려면 아래가 필요합니다.

## 준비물
1. **Mac 컴퓨터** (필수) — Xcode가 macOS에서만 실행됩니다.
   (본인 Mac이 없으면: 지인 Mac, 학교 실습실 Mac, 또는 클라우드 Mac 대여 이용)
2. **Xcode** (무료) — Mac App Store에서 설치.
3. **Apple Developer Program** (연 약 US$99) — 실제 기기 설치·배포에 필요.
   (본인 아이폰에 잠깐 테스트만 할 때는 무료 Apple ID로도 7일 임시 설치가 가능)

## 빌드 순서
1. Xcode에서 새 프로젝트 생성: iOS → App → SwiftUI 선택.
2. 이 폴더의 파일을 프로젝트에 추가:
   - MediNoteApp.swift (앱 진입점)
   - ContentView.swift (WebView 화면)
   - HealthKitManager.swift (건강 데이터, 사용 시)
   - index.html (앱에 포함할 웹 화면 — Bundle에 포함되도록 추가)
3. 건강 기능을 쓸 경우:
   - Signing & Capabilities → **HealthKit** 추가
   - Info.plist에 사용 목적 문구 추가:
     NSHealthShareUsageDescription = "복약·접종 안내를 돕기 위해 건강 데이터를 읽습니다. 데이터는 기기 안에 있습니다."
4. Signing & Capabilities → 본인 Apple 계정(Team) 선택.

## 테스트·배포 방법
- **내 아이폰에서 바로 테스트:** 아이폰을 Mac에 연결 → Xcode에서 기기 선택 → Run(▶).
- **다른 사람에게 테스트 배포:** **TestFlight** 사용 (App Store Connect에 업로드 후 초대).
- **정식 출시:** App Store Connect에서 심사 제출 → 승인 후 App Store 공개.

## 안내
- iOS 앱은 Mac + Xcode + (배포 시)유료 개발자 계정이 반드시 필요합니다.
- 웹페이지 버전(shared/index.html)은 Mac 없이도 브라우저에서 바로 열 수 있습니다.
- Apple Watch 건강 데이터는 아이폰 네이티브 앱의 HealthKit로만 접근 가능합니다.
