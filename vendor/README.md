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

## fonts/ — 글꼴 (#51 MN-51-3)

앱을 열 때마다 fonts.googleapis.com · cdn.jsdelivr.net 에 접속해 IP·기기 정보가 남던 것을 없애려고
글꼴도 담았습니다. `fonts/medinote-fonts.css` 를 `MediNote_app.html` 과 `증상신고_공유.html` 이 읽습니다.

| 파일 | 출처 | 라이선스 |
| --- | --- | --- |
| `Pretendard-{Regular,SemiBold,Bold,ExtraBold}.subset.woff2` | npm `pretendard` 1.3.9 `dist/web/static/woff2-subset/` 그대로 (앱이 쓰는 400·600·700·800) | SIL OFL 1.1 — `fonts/OFL-Pretendard.txt` |
| `Gaegu-{Regular,Bold}.subset.woff2` | Google Fonts 원본 TTF(gaegu v23)를 fonttools `pyftsubset` 로 Pretendard 의 `subset_glyphs.txt` 와 같은 글자(KS X 1001 한글 포함)만 남겨 woff2 로 | SIL OFL 1.1 — `fonts/OFL-Gaegu.txt` |

Nanum Pen Script 는 예전에 불러오기만 하고 어느 화면도 쓰지 않아 담지 않았습니다.
줄인 글자 목록 밖의 글자는 시스템 글꼴로 보입니다. 앱 셸 사본에는 `tools/build-packaged-app.py` 가
CSS 를 화면 안에 붙이고 글꼴 파일·라이선스를 index.html 옆에 둡니다.
