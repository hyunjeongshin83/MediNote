/* ============================================================
   MediNote 부트 스크립트
   ① 처방(RX) 데이터를 DB(API)에서 불러와 앱에 주입
   ② PWA 서비스워커 등록(오프라인) + 설치 프롬프트
   앱 HTML보다 먼저 defer 로드됩니다. 처방 데이터는 window.RX 에 주입합니다.
   ============================================================ */
(function () {
  // 허브와 동일한 Supabase (로그인·저장 공유)
  var SUPABASE_URL = "https://xaclqvveppvccdpebzsz.supabase.co";
  var SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhhY2xxdnZlcHB2Y2NkcGVienN6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3NTkzNzEsImV4cCI6MjA5OTMzNTM3MX0.qZ9qWV3kVmJW4hUwjP8N_PGddO37sJvLCHx-XaYLJ9U";

  function sbHeaders() {
    return { apikey: SUPABASE_ANON_KEY, Authorization: "Bearer " + SUPABASE_ANON_KEY };
  }

  // 처방 데이터를 DB에서 불러온다.
  // 우선순위: URL ?rx=처방ID → prescriptions 테이블 / 없으면 hub_state 의 'medit:rx' / 실패 시 앱 내장 데모 데이터 유지
  async function loadRx() {
    try {
      var params = new URLSearchParams(location.search);
      var rxId = params.get("rx") || localStorage.getItem("medit:rxid");
      var data = null;

      if (rxId) {
        localStorage.setItem("medit:rxid", rxId);
        var r1 = await fetch(SUPABASE_URL + "/rest/v1/prescriptions?id=eq." + encodeURIComponent(rxId) + "&select=*", { headers: sbHeaders() });
        if (r1.ok) { var rows1 = await r1.json(); if (rows1 && rows1[0]) data = rows1[0].data || rows1[0]; }
      }
      if (!data) {
        var r2 = await fetch(SUPABASE_URL + "/rest/v1/hub_state?key=eq.medit:rx&select=value", { headers: sbHeaders() });
        if (r2.ok) { var rows2 = await r2.json(); if (rows2 && rows2[0]) data = rows2[0].value; }
      }

      if (data && window.RX && typeof data === "object") {
        Object.assign(window.RX, data);          // 내장 데모 위에 DB 값 덮어쓰기
        refreshRxCard();
        console.log("[MediNote] 처방 데이터를 DB에서 불러왔습니다.");
      } else {
        console.log("[MediNote] DB에 처방 데이터 없음 — 내장 데모로 표시합니다.");
      }
    } catch (e) {
      console.warn("[MediNote] DB 로드 실패, 내장 데모 사용:", e.message);
    }
  }

  // DB에서 받은 처방을 상단 rx-card 에 반영 (앱 시작 화면에서 이미 보이도록)
  function refreshRxCard() {
    var RX = window.RX; if (!RX) return;
    var meds = (RX.meds || []).map(function (m) { return m.name + " " + m.dose; }).join(" · ");
    var elMeds = document.querySelector("#rx-card .rx-meds");
    if (elMeds && meds) elMeds.textContent = meds;
    var elDet = document.querySelector("#rx-card .rx-detail");
    if (elDet) elDet.textContent = (RX.hospital || "") + " " + (RX.doctor || "") + " · " + (RX.pharmacy || "") + " " + (RX.pharmacist || "");
  }
  window.MediNoteRefreshRx = refreshRxCard;

  // 처방을 DB에 저장(약국/병원 시스템이 QR 발급 시 호출하는 용도)
  window.MediNoteSaveRx = async function (rx) {
    var body = [{ key: "medit:rx", value: rx, updated_at: new Date().toISOString() }];
    var r = await fetch(SUPABASE_URL + "/rest/v1/hub_state", {
      method: "POST",
      headers: Object.assign(sbHeaders(), { "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" }),
      body: JSON.stringify(body)
    });
    return r.ok;
  };

  // ② PWA 서비스워커
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("sw.js").catch(function () {});
    });
  }
  // 설치 프롬프트(웹 홈추가). Play스토어 TWA에서는 자동 설치라 불필요하지만 웹 배포 겸용.
  var deferredPrompt = null;
  window.addEventListener("beforeinstallprompt", function (e) { e.preventDefault(); deferredPrompt = e; });
  window.MediNoteInstall = function () { if (deferredPrompt) { deferredPrompt.prompt(); deferredPrompt = null; } };

  if (document.readyState !== "loading") loadRx();
  else document.addEventListener("DOMContentLoaded", loadRx);
})();
