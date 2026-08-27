# 공공데이터포털(data.go.kr) 예방접종 API — 발급·연동 가이드

작성 2026-07-20 · 대상: MediNote 앱/페이지에서 질병관리청 예방접종 실데이터 연결
핵심: **활용신청 → serviceKey 발급 → 프록시(Supabase)에 키 넣고 호출**. 브라우저에서 직접 부르면 CORS로 막히고 키가 노출되므로, 프록시 한 단계를 반드시 둡니다.

---

## A. 키 발급 (data.go.kr에서 — 제가 직접 할 일)

1. **회원가입·로그인** — https://www.data.go.kr 에서 가입(간편/이메일).
2. **API 검색** — 검색창에 예: `코로나19 예방접종 현황`. 아래 3개를 각각 신청 권장.
   - 질병관리청 코로나19 예방접종 현황 — data.go.kr/data/15078166/openapi.do
   - 코로나19 예방접종 위탁의료기관 조회 — data.go.kr/data/15081240/openapi.do
   - (필요 시) 감염병 누리집 OPEN API — kdca.go.kr/npt
3. **활용신청** — API 상세페이지 우측 **[활용신청]** 클릭 → 활용목적(예: "복약·예방접종 관리 앱 개발"), 라이선스 동의 → 신청.
4. **승인 대기** — "자동승인" 표시 API는 **즉시** 승인. 심의형은 1~2일.
5. **인증키 확인** — 로그인 → **마이페이지 → 데이터활용 → Open API → 개발계정** → 해당 API 클릭.
   - 여기서 **일반 인증키(Encoding)** 와 **일반 인증키(Decoding)** 두 종류가 보입니다. (아래 C-키주의 참고)
   - 같은 화면에 **요청주소(엔드포인트)**, **요청변수**, **호출 예제**, 일일 트래픽(보통 개발계정 1,000~10,000건/일)이 있습니다. 이 페이지를 기준으로 코딩합니다.

> 인증키는 신청한 **모든 API에 공용**입니다(계정당 1개). API마다 다시 안 받아도 됩니다.

---

## B. 호출 형태 (엔드포인트 + serviceKey)

요청 URL은 대개 이런 모양입니다:
```
https://apis.data.go.kr/1790387/vaccineStatus/getVaccineStatus
   ?serviceKey=발급받은키
   &numOfRows=10&pageNo=1
   &returnType=JSON        (API에 따라 _type=json 인 경우도 있음 — 명세 확인)
```
- `numOfRows`·`pageNo` = 페이지네이션, `returnType/_type` = 응답 형식(JSON 권장).
- 나머지 요청변수(기준일자 등)는 그 API "요청변수" 표를 그대로 따릅니다.

---

## C. 브라우저에서 바로 못 붙는 이유 2가지 + 해결

**문제 1 · CORS** — data.go.kr API 대부분은 브라우저 직접 `fetch`를 허용하지 않습니다(응답에 CORS 헤더 없음 → "Failed to fetch"). 서버/프록시를 거쳐야 합니다.

**문제 2 · 키 노출** — serviceKey를 HTML/JS에 그대로 넣으면 누구나 소스에서 훔쳐 씁니다(트래픽 소진·차단 위험).

**해결 = 프록시 한 단계.** 이미 쓰는 **Supabase Edge Function**에 키를 숨기고, 프론트는 프록시만 부릅니다. 키는 서버 시크릿에만 존재.

### 키 주의 (가장 흔한 에러)
- URL 문자열에 **그대로 붙일 때 → Encoding 키** 사용.
- 코드에서 `URLSearchParams`/`params`로 넘겨 라이브러리가 자동 인코딩할 때 → **Decoding 키** 사용(안 그러면 이중 인코딩).
- 잘못 맞추면 `SERVICE_KEY_IS_NOT_REGISTERED_ERROR` 또는 `SERVICE ERROR`가 뜹니다. 아래 예제는 **Decoding 키 + 자동 인코딩**으로 통일했습니다.

---

## D. Supabase 프록시 예제 (복붙용)

`supabase/functions/gov-data/index.ts`
```ts
// data.go.kr 프록시 — 키를 숨기고 CORS를 해결
import { serve } from "https://deno.land/std/http/server.ts";

const KEY = Deno.env.get("DATA_GO_KR_KEY")!;   // Decoding 키를 시크릿으로
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const { searchParams } = new URL(req.url);

  // 프론트가 넘기는 값: base(엔드포인트), 그 외 파라미터
  const base = searchParams.get("base");            // 예: 요청주소
  if (!base) return json({ error: "base 필요" }, 400);

  const qs = new URLSearchParams();
  qs.set("serviceKey", KEY);                        // 자동 인코딩됨(Decoding 키)
  qs.set("returnType", "JSON");
  qs.set("numOfRows", searchParams.get("numOfRows") ?? "10");
  qs.set("pageNo", searchParams.get("pageNo") ?? "1");
  // 필요 요청변수 전달 (base/numOfRows/pageNo 제외한 나머지 그대로)
  for (const [k, v] of searchParams) {
    if (!["base", "numOfRows", "pageNo"].includes(k)) qs.set(k, v);
  }

  const r = await fetch(`${base}?${qs}`);
  const text = await r.text();                      // JSON/ XML 그대로 전달
  return new Response(text, {
    status: r.status,
    headers: { ...CORS, "Content-Type": r.headers.get("content-type") ?? "application/json" },
  });
});

function json(o: unknown, status = 200) {
  return new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
```

배포 + 시크릿:
```bash
supabase functions deploy gov-data
supabase secrets set DATA_GO_KR_KEY="여기에_Decoding_키_붙여넣기"
```

### 프론트(앱/페이지)에서 호출 — 키 없이 프록시만
```js
const PROXY = window.MEDINOTE_CONFIG.functionsUrl + "/gov-data";
// 프로젝트 주소는 medinote.config.js 한 곳에 있습니다.
async function loadVaccineStatus() {
  const base = "https://apis.data.go.kr/1790387/vaccineStatus/getVaccineStatus"; // 실제 요청주소
  const url = PROXY + "?base=" + encodeURIComponent(base) + "&numOfRows=10&pageNo=1&baseDate=20260101";
  const r = await fetch(url);
  const data = await r.json();
  console.log(data);   // 화면 카드/표에 렌더
}
```
프론트에는 serviceKey가 전혀 없고, CORS도 프록시가 해결합니다.

---

## E. 내가 할 일 체크리스트

- [ ] data.go.kr 회원가입·로그인
- [ ] 예방접종 API 3개 **활용신청**(자동승인은 즉시)
- [ ] 마이페이지에서 **인증키(Decoding)** 와 **요청주소·요청변수** 복사
- [ ] Supabase에 `gov-data` Edge Function 배포
- [ ] `supabase secrets set DATA_GO_KR_KEY=...` 로 키 저장(코드엔 절대 안 넣음)
- [ ] 앱/페이지에서 `PROXY?base=...` 형태로 호출 → 화면에 렌더
- [ ] (선택) 응답을 `hub_state`에 캐시해 오프라인·속도 대응

---

## 참고
- CORS·키 노출 때문에 "브라우저에서 직접 호출"은 실서비스에 부적합합니다. 프록시(Supabase)가 표준 해법입니다.
- 반대로 **WHO GHO / CDC 오픈데이터**는 키·CORS 문제가 없어 프론트에서 바로 붙습니다(예방접종_데이터API.html 상단 패널이 그 예).
- 승인 후에도 값이 안 오면: ① Encoding/Decoding 키 혼동 ② returnType 파라미터명(_type vs returnType) ③ 일일 트래픽 초과 — 이 3개를 순서대로 확인하세요.
