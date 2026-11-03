#!/usr/bin/env python3
"""앱이 바깥으로 접속하는 주소의 장부 — 장부에 없는 주소가 들어오면 CI 가 멈춥니다 (#51 MN-51-2)

건강 데이터가 어디로 가는지는 코드가 부르는 주소로 정해집니다. 그래서 주소 목록 자체를 여기 두고,
CLAUDE.md §3 과 PRIVACY.md 가 이 목록을 따르게 합니다. 새 주소를 넣으려면 이 파일에 「왜」를 적어야 합니다.

    python3 tools/egress-check.py          장부 밖 주소가 있으면 1
    python3 tools/egress-check.py --list   지금 코드에 있는 주소 전부
    python3 tools/egress-check.py --selftest   이어 붙인 주소 꼴을 잡는지 (#54 Codex)

보는 파일: MediNote_app.html · MediNote.sw.js · medinote.config.js (앱 화면 사본 3벌은 MediNote_app.html 과 같아야 하므로 뺍니다)
        + MediNote_app.html 안에 base64 로 박은 「증상 신고·공유」 사본(window.__MNRP_SRC)을 풀어서 (#130 MN-130-1)
"""
import base64, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ["MediNote_app.html", "MediNote.sw.js", "medinote.config.js"]
# 네이티브 껍데기(Kotlin · Swift)도 봅니다 — 안드로이드 셸이 play.google.com 을 여는 것처럼 바깥 주소가 들어갈 수 있습니다 (PR #52 Codex)
GLOBS = ["MediNote_apps_0706/android/app/src/main/java/**/*.kt", "MediNote_apps_0706/ios/**/*.swift"]
def files():
    out = [ROOT / f for f in FILES]
    for g in GLOBS: out += sorted(ROOT.glob(g))
    return [p for p in out if p.exists()]

# base64 로 박은 화면 사본 — 정규식은 base64 글자 속 주소를 못 봅니다. 풀어서 같은 규칙으로 훑습니다 (#130 MN-130-1)
EMBED = re.compile(r'window\.__MNRP_SRC\s*=\s*["\']([A-Za-z0-9+/=]+)["\']')
def embedded(text):
    out = []
    for m in EMBED.finditer(text):
        try: out.append(base64.b64decode(m.group(1)).decode("utf-8"))
        except Exception: out.append("")   # 풀리지 않는 사본은 빈 글로 — 아래 main 이 실패로 알립니다
    return out
def sources():
    """(이름, 글) — 파일 본문과, 그 안에 박힌 사본을 푼 글"""
    for p in files():
        f = str(p.relative_to(ROOT)); text = p.read_text(encoding="utf-8")
        yield f, text
        for i, inner in enumerate(embedded(text)):
            yield f"{f}#__MNRP_SRC" + (f"[{i}]" if i else ""), inner

# 호스트 → 무엇이 가는가. 「건강 데이터」가 가는 곳은 ★.
ALLOWED = {
    "supabase.co":               "★ Supabase (도쿄) — 프로필·측정값·증상 기록·복약 hub_state. 사용자가 저장을 눌렀을 때 (CLAUDE.md §3)",
    "functions.supabase.co":     "★ 엣지 함수 ai-helper — 프로필·최근 증상·복용약·대화를 받아 Anthropic(미국)으로 넘김. 앱은 api.anthropic.com 을 직접 부르지 않음. "
                                 "「증상 신고·공유」의 보건소 이메일 찾기는 gov-data 함수에 보건소 이름을 보냄",
    "accounts.google.com":       "Google 로그인",
    # 글꼴(Pretendard · Gaegu)은 vendor/fonts/ 에서 같은 출처로 읽습니다 — fonts.googleapis.com · fonts.gstatic.com · cdn.jsdelivr.net 을 뺐습니다 (#51 MN-51-3)
    "hyunjeongshin83.github.io": "웹앱 주소 — 안내 문구 속 링크 (#20 MN-20-4)",
    # 아래 넷은 앱 안 「증상 신고·공유」 사본(window.__MNRP_SRC)에서 나옵니다 — 이 장부가 사본 안을 보기 시작하며 드러났습니다 (#130 MN-130-1)
    "nominatim.openstreetmap.org": "★ 위치 — 「내 위치로 보건소 찾기」를 누르고 위치를 허락하면 위도·경도가 OpenStreetMap(Nominatim · 해외 공개 서버)으로 감. "
                                 "PRIVACY.md · CLAUDE.md §3 · 단추 앞 안내는 #130 MN-130-3",
    "apis.data.go.kr":           "공공데이터포털 주소 — 직접 부르지 않고 gov-data 엣지 함수에 base 인자로 넘기는 글자",
    "kaers.drugsafe.or.kr":      "의약품 부작용 보고(KAERS) 누리집 링크 — 사용자가 단추를 누르면 엶. 신고서 본문은 클립보드에 복사되고 사용자가 붙여 넣음",
    "accounts.kakao.com":        "카카오톡 친구 고르기 페이지 링크 — 사용자가 단추를 누르면 엶. 신고서 본문은 클립보드에 복사되고 사용자가 붙여 넣음",
    "www.google.com":            "보건소 이메일을 못 찾았을 때 「<보건소 이름> 이메일 주소」 검색을 엶 — 보건소 이름이 검색어로 감",
    "play.google.com":           "Health Connect 설치 안내 링크 (안드로이드 셸)",
    "nip.kdca.go.kr":            "질병관리청 안내 링크",
    "nominatim.openstreetmap.org": "★ 보건소 찾기 — 단추를 누르면 기기 위치(위도·경도)가 주소 변환에 쓰여 OpenStreetMap(해외 공개 서버)으로 감. 단추 위 안내 · PRIVACY 2-6 (#130 MN-130-3)",
    "www.w3.org":                "SVG 네임스페이스 — 요청 없음",
    "appassets.androidplatform.net": "안드로이드 WebView 자산 로더의 가상 주소 — 앱 안의 파일을 읽을 뿐 바깥으로 나가지 않음",
}
FORBIDDEN = {
    "api.anthropic.com": "앱에서 직접 부르면 건강 데이터가 서버 규칙 없이 미국으로 나갑니다 — 반드시 ai-helper 경유 (#44 MN-44-1 · #51 MN-51-1)",
}

HOST = r'([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,})'

Q = r'["\'`]'
def hosts_in(text):
    # 1) 통째로 적힌 주소: https://host/...
    hosts = set(re.findall(r'https?://' + HOST, text))
    # 2) 조각으로 이어 붙이는 주소: "https://" + REF + ".supabase.co"  (#52 Sourcery)
    #    + 뒤에 따옴표로 「.도메인」 꼴이 오면 호스트 꼬리로 봅니다 — 장부에는 꼬리(supabase.co)가 적혀 있습니다.
    #    + 없이 홀로 있는 ".modal.open" 같은 선택자는 안 잡습니다 (#54 Codex)
    hosts |= set(re.findall(r'\+\s*' + Q + r'\.' + HOST + Q, text))
    # 3) 규약 바로 뒤에 호스트를 통째로 이어 붙인 것: "https://" + "api.anthropic.com"  (#54 Codex)
    hosts |= set(re.findall(r'https?://' + Q + r'\s*\+\s*' + Q + HOST, text))
    # 4) 템플릿 문자열: `https://${ref}.supabase.co`
    hosts |= set(re.findall(r'https?://\$\{[^}]*\}\.' + HOST, text))
    # 5) 금지 호스트의 꼬리가 따옴표 안에 홀로 있어도 잡습니다: const suffix = ".anthropic.com"; fetch("https://api" + suffix)  (PR #60 Codex)
    #    허용 호스트는 2)·3) 으로 충분하고, 금지 호스트만은 조각이 어디 있든 보여야 합니다.
    for f in FORBIDDEN:
        tail = f.split('.', 1)[1] if f.count('.') >= 2 else f
        if any(h == tail or h.endswith('.' + tail) for h in hosts): continue   # 온전한 호스트가 이미 잡혔으면 꼬리는 따로 안 더함
        if re.search(Q + r'\.?(?:[a-z0-9-]+\.)*' + re.escape(tail) + Q, text): hosts.add(tail)
    return hosts

SELFTEST = [   # (코드 조각, 잡혀야 하는 호스트)
    ('fetch("https://api.example.com/x")',               {"api.example.com"}),
    ('"https://" + REF + ".supabase.co"',                {"supabase.co"}),
    ('"https://" + "api.anthropic.com" + "/v1"',         {"api.anthropic.com"}),
    ("'https://' + 'api.anthropic.com'",                 {"api.anthropic.com"}),
    ('`https://${ref}.functions.supabase.co/ai-helper`', {"functions.supabase.co"}),
    ('const suffix = ".anthropic.com"; fetch("https://api" + suffix)', {"anthropic.com"}),
    ('document.querySelector(".modal.open")',            set()),
    ('el.classList.add("is.open")',                      set()),
]
# base64 사본 안의 주소도 보이는지 (#130 MN-130-1)
def _b64(t): return base64.b64encode(t.encode("utf-8")).decode("ascii")
SELFTEST_EMBED = [
    ('window.__MNRP_SRC="' + _b64('fetch("https://api.anthropic.com/v1/messages")') + '";', {"api.anthropic.com"}),
    ("window.__MNRP_SRC = '" + _b64('fetch("https://nominatim.openstreetmap.org/reverse")') + "';", {"nominatim.openstreetmap.org"}),
    ('window.__MNRP_SRC="' + _b64('<p>주소 없음</p>') + '";',                                   set()),
]
def embedded_hosts(code):
    h = set()
    for inner in embedded(code): h |= hosts_in(inner)
    return h
def selftest():
    bad = [(c, hosts_in(c), want) for c, want in SELFTEST if hosts_in(c) != want]
    bad += [(c[:40] + "…", embedded_hosts(c), want) for c, want in SELFTEST_EMBED if embedded_hosts(c) != want]
    for c, got, want in bad: print(f"selftest 실패: {c!r} → {sorted(got)} (기대 {sorted(want)})")
    n = len(SELFTEST) + len(SELFTEST_EMBED)
    print(f"egress-check --selftest: {n - len(bad)}/{n}")
    return 1 if bad else 0

def main():
    if "--selftest" in sys.argv: return selftest()
    found = {}; broken = []
    for f, text in sources():
        if "#__MNRP_SRC" in f and not text: broken.append(f); continue
        for h in hosts_in(text):
            found.setdefault(h, set()).add(f)
    if broken:
        print("풀 수 없는 base64 사본: " + ", ".join(broken) + " — tools/embed-report-screen.py 로 다시 박으세요", file=sys.stderr); return 1
    if "--list" in sys.argv:
        for h in sorted(found): print(f"{h:32} {', '.join(sorted(found[h]))}")
        return 0
    bad = 0
    for h in sorted(found):
        fb = next((f for f in FORBIDDEN if h == f or f.endswith('.' + h) or h.endswith('.' + f)), None)   # 꼬리(anthropic.com)도 금지로 (PR #60 Codex)
        if fb:
            bad += 1; print(f"금지: {h} ({', '.join(sorted(found[h]))}) — {FORBIDDEN[fb]}")
            continue
        if not any(h == a or h.endswith("." + a) for a in ALLOWED):
            bad += 1; print(f"장부에 없음: {h} ({', '.join(sorted(found[h]))}) — tools/egress-check.py 의 ALLOWED 에 「왜」와 함께 적으세요")
    if bad:
        print(f"\n바깥 주소 {bad}곳이 장부와 다릅니다.", file=sys.stderr); return 1
    print(f"egress-check: 바깥 주소 {len(found)}곳 전부 장부에 있음")
    return 0

if __name__ == "__main__":
    sys.exit(main())
