# MediNote Google 로그인 켜기 (관리자 1회 설정)

Google 로그인이 안 되는 이유는 앱 문제가 아니라, **Supabase에 Google 공급자가 아직 켜지지 않았기** 때문입니다. 아래 3단계를 팀(관리자)이 한 번만 하면 됩니다. (사용자는 설정 필요 없음)

전제: 앱을 **https 주소로 배포**한 상태여야 합니다. `file://`로 직접 열거나 미리보기(iframe)에서는 Google 로그인이 동작하지 않습니다.

---

## 1) Google Cloud Console — OAuth 클라이언트 만들기
1. https://console.cloud.google.com → 프로젝트 생성(또는 선택)
2. **API 및 서비스 → OAuth 동의 화면** 구성
   - User Type: 외부(External), 앱 이름·이메일 입력, 저장
   - 테스트 단계면 **테스트 사용자**에 로그인할 Google 계정(교수님·본인 이메일)을 추가
3. **사용자 인증 정보 → 사용자 인증 정보 만들기 → OAuth 클라이언트 ID**
   - 애플리케이션 유형: **웹 애플리케이션**
   - **승인된 리디렉션 URI**에 아래를 그대로 추가:
     ```
     https://xaclqvveppvccdpebzsz.supabase.co/auth/v1/callback
     (프로젝트를 옮기면 medinote.config.js 의 REF 를 바꾸고, 이 주소도 새 ref 로 다시 등록하세요)
     ```
   - 만들기 → **클라이언트 ID**와 **클라이언트 보안 비밀(Secret)** 복사

## 2) Supabase — Google 공급자 켜기
1. Supabase 대시보드 → **Authentication → Providers → Google**
2. **Enable** 켜고, 위에서 복사한 **Client ID / Client Secret** 붙여넣기 → 저장

## 3) Supabase — Redirect URL 등록
1. **Authentication → URL Configuration**
2. **Site URL**: 배포한 앱 주소 (예: `https://아이디.github.io/저장소/MediNote_app.html`)
3. **Redirect URLs**에 아래를 추가(끝에 별표로 범위 허용 권장):
   ```
   https://아이디.github.io/저장소/*
   ```
   - GitHub Pages가 아니라 다른 호스팅이면 그 주소를 넣으세요.

---

## 4) 테스트
- 배포된 https 주소에서 앱을 열고, 우측 상단 **로그인 → Google로 로그인**
- 구글 계정 선택 → 다시 앱으로 돌아오며 로그인 완료(계정 칩에 이름 표시)
- 이제 그 Google 계정으로 증상·복약·신고 기록이 저장·조회됩니다.

## 자주 나는 실패 & 해결
- **provider is not enabled**: 2단계(공급자 Enable)가 안 된 것 → 켜기
- **redirect_uri_mismatch**: 1단계 리디렉션 URI가 `.../auth/v1/callback`과 정확히 같아야 함
- **로그인 후 앱으로 안 돌아옴 / 오류**: 3단계 Redirect URLs에 앱 주소가 없음 → 추가
- **access_denied**: OAuth 동의 화면이 ‘테스트’ 상태 → 로그인할 계정을 테스트 사용자에 추가(또는 게시)
- **file://·미리보기에서 안 됨**: 정상입니다. https 배포 주소에서 여세요.

> 설정 전까지는 앱의 **본인 아이디로 로그인**으로 바로 테스트할 수 있습니다(아이디만 입력하면 그 계정으로 기록이 쌓임). Google 로그인은 여러 기기에서 같은 계정으로 이어질 때 유용합니다.

MediNote · 정보 제공·상담 연결까지만, 판정·처방은 하지 않습니다.
