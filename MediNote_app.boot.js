/* ============================================================
   MediNote 부트 스크립트
   ① 처방(RX) 데이터를 DB(API)에서 불러와 앱에 주입
   ② PWA 서비스워커 등록(오프라인) + 설치 프롬프트
   앱 HTML보다 먼저 defer 로드됩니다. 처방 데이터는 window.RX 에 주입합니다.
   ============================================================ */
(function () {
  // 허브와 동일한 Supabase (로그인·저장 공유)
  // 주소·키는 medinote.config.js 한 곳에서 온다. 이 스크립트를 단독으로 쓰는
  // 경우를 위해 값을 그대로 적어 둔 대비책을 남긴다.
  var CFG = window.MEDINOTE_CONFIG || {
    url: "https://xaclqvveppvccdpebzsz.supabase.co",
    key: "sb_publishable_i0msp00o_4-JOBp9JjZLww_VExbio2b"
  };
  var SUPABASE_URL = CFG.url;
  var SUPABASE_KEY = CFG.key;

  function sbHeaders() {
    // 로그인했으면 앱의 공용 계층이 들고 있는 세션 토큰으로, 아니면 publishable 키로.
    var kv = window.MediNoteKV;
    if (kv && kv.token && kv.token()) return kv.headers();
    return { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY };
  }

  // prescriptions · hub_state 직접 조회는 익명 목록 열거를 막느라 닫혔다.
  // 키/ID 를 정확히 아는 1건씩만 응답하는 SECURITY DEFINER 함수로 나간다.
  async function rpc(fn, body) {
    var r = await fetch(SUPABASE_URL + "/rest/v1/rpc/" + fn, {
      method: "POST",
      headers: Object.assign(sbHeaders(), { "Content-Type": "application/json" }),
      body: JSON.stringify(body || {})
    });
    if (!r.ok) throw new Error("RPC " + fn + " HTTP " + r.status);
    return r.json();
  }

  // 처방 데이터를 DB에서 불러온다.
  // 우선순위: URL ?rx=처방ID → get_prescription(id) / 없으면 kv_get('medit:rx') / 실패 시 앱 내장 데모 데이터 유지
  async function loadRx() {
    try {
      var params = new URLSearchParams(location.search);
      var rxId = params.get("rx") || localStorage.getItem("medit:rxid");
      var data = null;

      if (rxId) {
        localStorage.setItem("medit:rxid", rxId);
        try { data = await rpc("get_prescription", { p_id: rxId }); } catch (e) { data = null; }
      }
      if (!data) {
        try { data = await rpc("kv_get", { p_key: "medit:rx" }); } catch (e) { data = null; }
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
  // 익명 쓰기는 닫혀 있다 — medit:rx 는 로그인한 계정이 본인 행으로만 저장한다.
  window.MediNoteSaveRx = async function (rx) {
    var kv = window.MediNoteKV, uid = kv && kv.userId && kv.userId();
    if (!uid) { console.warn("[MediNote] 처방 저장은 로그인 후에만 가능합니다."); return false; }
    var body = [{ key: "medit:rx", value: rx, user_id: uid, is_public: false, updated_at: new Date().toISOString() }];
    var r = await fetch(SUPABASE_URL + "/rest/v1/hub_state", {
      method: "POST",
      headers: Object.assign(kv.headers(), { "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" }),
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
