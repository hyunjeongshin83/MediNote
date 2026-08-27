# vendor — 앱이 반드시 필요로 하는 외부 라이브러리 사본

앱 본문 UI 전체가 React 로 그려지기 때문에, CDN 에 못 닿으면 사용자는 아무 안내도
없이 빈 화면만 봅니다. 병원·학교·관공서 와이파이가 CDN 을 막는 경우가 드물지 않아
저장소에 직접 담아 두고 같은 출처에서 서빙합니다.

| 파일 | 출처 | 버전 |
| --- | --- | --- |
| `react-18.production.min.js` | npm `react` (umd/react.production.min.js) | 18.3.1 |
| `react-dom-18.production.min.js` | npm `react-dom` (umd/react-dom.production.min.js) | 18.3.1 |
| `supabase-js-2.umd.js` | npm `@supabase/supabase-js` (dist/umd/supabase.js) | 2.112.4 |
| `qrcodejs-1.0.0.min.js` | npm `qrcodejs` (qrcode.min.js) | 1.0.0 |

갱신하려면 npm 에서 같은 경로의 파일을 받아 덮어쓰고, `MediNote.sw.js` 의 캐시
버전(`CACHE`)을 올려 주세요.

폰트(Pretendard·Gaegu·Nanum Pen Script)는 담지 않았습니다. 없으면 시스템 기본
한글 글꼴로 대체될 뿐 화면이 깨지지 않기 때문입니다.
