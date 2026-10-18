/* ============================================================
   MediNote 접속 설정 — 프로필 DB 주소는 여기 한 곳에만 둡니다.

   다른 Supabase 프로젝트로 옮길 때는 아래 REF 와 KEY 두 줄만 고치면
   앱·증상신고·오늘기록·안내카드 페이지가 한꺼번에 따라옵니다.

   KEY 는 publishable(공개) 키입니다. 브라우저에 노출되는 것이 정상이며,
   실제 접근 통제는 행 수준 보안(RLS)과 RPC 함수가 합니다.
   시크릿 키는 절대 여기 두지 마세요.
   ============================================================ */
(function () {
  var REF = "xaclqvveppvccdpebzsz";
  var KEY = "sb_publishable_i0msp00o_4-JOBp9JjZLww_VExbio2b";

  window.MEDINOTE_CONFIG = {
    ref: REF,
    url: "https://" + REF + ".supabase.co",
    functionsUrl: "https://" + REF + ".functions.supabase.co",
    /* AI 도우미 엣지 함수의 주소 이름(slug). 대시보드에서 함수를 만들면 Supabase 가
       bright-processor 같은 이름을 멋대로 붙이고 그 이름은 나중에 못 바꿉니다.
       프로젝트를 옮길 때 실제로 올라간 이름을 여기에 적어 주세요. */
    aiFunction: "ai-helper",
    key: KEY,
    /* 「빠른 체험」을 기기 번호(g_) 대신 익명 계정(signInAnonymously)으로 — #55 MN-55-1.
       true 로 바꾸기 전에 MN-55-2 정책 적용 · 대시보드에서 Anonymous sign-ins · Manual linking · Turnstile (MN-55-3). */
    anonAuth: false,
    /* 설치한 웹앱(PWA) 아이콘에 「시간이 지났는데 안 먹은 복용 수」 숫자를 — Badging API 실험 (#97 MN-97-1).
       기본 꺼짐. 켜기 전에 MN-97-2 (홈 화면에 숫자가 남에게 보임) 결정. */
    appBadge: false
  };
})();
