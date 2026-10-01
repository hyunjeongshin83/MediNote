#!/usr/bin/env python3
"""앱이 바깥으로 접속하는 주소의 장부 — 장부에 없는 주소가 들어오면 CI 가 멈춥니다 (#51 MN-51-2)

건강 데이터가 어디로 가는지는 코드가 부르는 주소로 정해집니다. 그래서 주소 목록 자체를 여기 두고,
CLAUDE.md §3 과 PRIVACY.md 가 이 목록을 따르게 합니다. 새 주소를 넣으려면 이 파일에 「왜」를 적어야 합니다.

    python3 tools/egress-check.py          장부 밖 주소가 있으면 1
    python3 tools/egress-check.py --list   지금 코드에 있는 주소 전부

보는 파일: MediNote_app.html · MediNote.sw.js · medinote.config.js (앱 화면 사본 3벌은 MediNote_app.html 과 같아야 하므로 뺍니다)
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ["MediNote_app.html", "MediNote.sw.js", "medinote.config.js"]

# 호스트 → 무엇이 가는가. 「건강 데이터」가 가는 곳은 ★.
ALLOWED = {
    "supabase.co":               "★ Supabase (도쿄) — 프로필·측정값·증상 기록·복약 hub_state. 사용자가 저장을 눌렀을 때 (CLAUDE.md §3)",
    "functions.supabase.co":     "★ 엣지 함수 ai-helper — 프로필·최근 증상·복용약·대화를 받아 Anthropic(미국)으로 넘김. 앱은 api.anthropic.com 을 직접 부르지 않음",
    "people.googleapis.com":     "생년월일 — Google 로그인 때 People API 에서 받아 옴 (#22 ⑤)",
    "www.googleapis.com":        "OAuth scope 문자열(user.birthday.read) — 요청 주소가 아니라 권한 이름",
    "accounts.google.com":       "Google 로그인",
    "fonts.googleapis.com":      "글꼴(Gaegu · Nanum Pen Script) — 앱을 열 때 Google 에 IP·기기 정보가 감. 건강 데이터 없음 (#51)",
    "fonts.gstatic.com":         "위 글꼴 파일",
    "cdn.jsdelivr.net":          "글꼴(Pretendard) — 앱을 열 때 jsDelivr 에 IP·기기 정보가 감. 건강 데이터 없음 (#51)",
    "hyunjeongshin83.github.io": "웹앱 주소 — 안내 문구 속 링크 (#20 MN-20-4)",
    "play.google.com":           "Health Connect 설치 안내 링크 (안드로이드 셸)",
    "nip.kdca.go.kr":            "질병관리청 안내 링크",
    "www.w3.org":                "SVG 네임스페이스 — 요청 없음",
}
FORBIDDEN = {
    "api.anthropic.com": "앱에서 직접 부르면 건강 데이터가 서버 규칙 없이 미국으로 나갑니다 — 반드시 ai-helper 경유 (#44 MN-44-1 · #51 MN-51-1)",
}

HOST = r'([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,})'

def hosts_in(text):
    # 1) 통째로 적힌 주소: https://host/...
    hosts = set(re.findall(r'https?://' + HOST, text))
    # 2) 조각으로 이어 붙이는 주소: "https://" + REF + ".supabase.co"  (#52 Sourcery)
    #    따옴표 안이 「.도메인」 꼴이면 호스트 꼬리로 봅니다 — 장부에는 꼬리(supabase.co)가 적혀 있습니다
    hosts |= set(re.findall(r'["\']\.' + HOST + r'["\']', text))
    return hosts

def main():
    found = {}
    for f in FILES:
        p = ROOT / f
        if not p.exists(): continue
        for h in hosts_in(p.read_text(encoding="utf-8")):
            found.setdefault(h, set()).add(f)
    if "--list" in sys.argv:
        for h in sorted(found): print(f"{h:32} {', '.join(sorted(found[h]))}")
        return 0
    bad = 0
    for h in sorted(found):
        if h in FORBIDDEN:
            bad += 1; print(f"금지: {h} ({', '.join(sorted(found[h]))}) — {FORBIDDEN[h]}")
            continue
        if not any(h == a or h.endswith("." + a) for a in ALLOWED):
            bad += 1; print(f"장부에 없음: {h} ({', '.join(sorted(found[h]))}) — tools/egress-check.py 의 ALLOWED 에 「왜」와 함께 적으세요")
    if bad:
        print(f"\n바깥 주소 {bad}곳이 장부와 다릅니다.", file=sys.stderr); return 1
    print(f"egress-check: 바깥 주소 {len(found)}곳 전부 장부에 있음")
    return 0

if __name__ == "__main__":
    sys.exit(main())
