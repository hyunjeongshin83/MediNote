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
    key: KEY
  };
})();
