#!/usr/bin/env python3
"""낭독 영역 밖의 「글이 런타임에 들어오는 칸」을 알려 줍니다 — 경고만, 실패시키지 않습니다 (#174 MN-174-2)

왜: 낭독 영역(aria-live)을 id 목록에 한 줄씩 더하는 고침이 세 번 되풀이됐습니다 (MN-31-1 → MN-136-1 → MN-154-1 → MN-174-1).
    조사하는 사람이 앱을 볼 때마다 목록 밖의 칸을 하나 찾는 구조라서, 새 칸이 생기면 CI 가 먼저 알려 주게 합니다.
무엇: MediNote_app.html 에서 el("id") · document.getElementById("id") 뒤에 .textContent= · .innerHTML= · .innerText= · .insertAdjacentHTML( 로
      글을 넣는 id 를 모으고, 그 가운데 낭독이 안 되는 칸을 알려 줍니다.
      낭독이 되는 칸 = aria-live 로 켜는 목록(querySelectorAll)에 있는 id, 또는 태그에 role=alert|status|log · aria-live 가 있는 id.
      단추(<button>)와 아래 NOT_STATUS 에 이유를 적어 둔 칸은 뺍니다.
      변수에 담아 쓰는 길(var out=el("a"); out.innerHTML=…)도 봅니다 — 같은 변수 이름이 다른 칸에 다시 쓰이면 둘 다 후보로 잡힐 수 있습니다.
한계: 정규식이라 함수 인자로 넘기거나 객체 속성에 담아 쓰는 길은 못 봅니다. 「없다」는 뜻이 아니라 「이 방법으로는 못 찾았다」입니다.
      후보가 실제 상태 알림인지는 사람이 판단합니다 — 낭독이 필요 없는 표시 칸은 NOT_STATUS 에 이유와 함께 더하세요.

    python3 tools/live-check.py            후보를 ::warning 으로 알림 (항상 0)
    python3 tools/live-check.py --list     글이 들어오는 id 전부와 낭독 여부
    python3 tools/live-check.py --selftest 모의 글로 후보를 가려내는지 (실패하면 1)
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "MediNote_app.html"

# 글이 들어오지만 상태·결과를 알리는 칸이 아니라 표시 칸인 것 — 이유를 꼭 적는다. 새 후보를 여기로 옮기는 것은 사람이 정한 뒤에.
NOT_STATUS = {
    "mncardBody": "복약 카드 본문 — 사용자가 연 화면의 내용 영역이지 상태 알림이 아님",
    "mnlg-av": "로그인 시트 머리의 아바타 글자 — 장식",
    "mnlg-hd": "로그인 시트의 제목 줄 — 시트를 열 때 한 번 정해지는 제목",
    "mnlg-cur": "로그인 시트의 「현재 로그인」 표시 — 로그인 결과는 #mnlg-status(「로그인되었습니다.」)가 알림, 이 칸은 표시",
    "mnlg-sub": "로그인 시트의 안내 줄 — 로그인 결과는 #mnlg-status 가 알림, 이 칸은 표시",
    "mnlg-nm": "로그인 시트에 보이는 이름 — 표시",
    "mnsy-list": "증상 기록 시트의 「최근 기록」 목록 — 저장 결과는 #mnsy-st 가 알림, 이 칸은 목록 표시",
    "mncardOv": "복약 카드 시트의 바깥 틀 — 시트 마크업을 한 번 넣는 칸",
    "mnhwOv": "건강 기기 시트의 바깥 틀 — 시트 마크업을 한 번 넣는 칸",
    "mnmdOv": "복약 알림 시트의 바깥 틀 — 시트 마크업을 한 번 넣는 칸",
    "mnmdList": "복약 알림 시트의 일정 목록 — 사용자가 연 시트의 내용 표시 (알림 꺼짐 같은 상태는 #mnmdNotifBox)",
    "root": "React 마운트 지점 — 화면 전체가 들어가는 칸",
    "mnmd-pill": "복약 알림 알약(role=button, aria-label 이 있음) — 같은 변수 이름 pill 이 로그인 알약에도 쓰여 잡힌 것 포함",
}

WRITE = re.compile(
    r'(?:\bel|document\.getElementById)\(\s*["\']([A-Za-z][\w-]*)["\']\s*\)\s*\.(?:textContent|innerHTML|innerText)\s*='
    r'|(?:\bel|document\.getElementById)\(\s*["\']([A-Za-z][\w-]*)["\']\s*\)\s*\.insertAdjacentHTML\(')
LIVE_LIST = re.compile(r'querySelectorAll\(\s*"([^"]+)"\s*\)\s*\.forEach\(\s*function\s*\(\s*\w+\s*\)\s*\{\s*\w+\.setAttribute\(\s*"aria-live"')

ASSIGN = re.compile(r'\b(?:var|let|const)\s+([A-Za-z_]\w*)\s*=\s*(?:\bel|document\.getElementById)\(\s*["\']([A-Za-z][\w-]*)["\']\s*\)')
NEAR = 700   # 담은 곳에서 이만큼(글자) 안의 쓰기만 같은 변수로 봅니다 — e · s 처럼 짧은 이름이 다른 함수에서 다시 쓰여 잡히는 것을 줄임
def var_write_ids(text):
    """var out=el("a") 로 담은 변수에, 담은 곳 근처에서 out.textContent= · out.innerHTML= · out.insertAdjacentHTML( 로 글을 넣는 id (한 글자 이름도 봅니다)"""
    out = set()
    for m in ASSIGN.finditer(text):
        name = re.escape(m.group(1))
        rest = text[m.end(): m.end() + NEAR]
        if re.search(r'\b%s\.(?:textContent|innerHTML|innerText)\s*=(?!=)|\b%s\.insertAdjacentHTML\(' % (name, name), rest):
            out.add(m.group(2))
    return out

def tag_of(text, i):
    m = re.search(r'<([a-zA-Z][\w-]*)[^<>]*\bid=\\?["\']%s\\?["\'][^<>]*>' % re.escape(i), text)
    return (m.group(1).lower(), m.group(0)) if m else (None, "")

def analyse(text):
    """(글이 들어오는 id 들, 낭독이 켜지는 id 집합, 후보 목록, 건너뛴 것 {id: 이유})"""
    ids = {}
    for m in WRITE.finditer(text):
        ids.setdefault(m.group(1) or m.group(2), 0)
    for i in var_write_ids(text):
        ids.setdefault(i, 0)
    covered, covered_cls = set(), set()
    for m in LIVE_LIST.finditer(text):
        covered |= {x.strip()[1:] for x in m.group(1).split(",") if x.strip().startswith("#")}
        covered_cls |= {x.strip()[1:] for x in m.group(1).split(",") if x.strip().startswith(".")}
    cand, skipped = [], {}
    for i in sorted(ids):
        tag, raw = tag_of(text, i)
        classes = set((re.search(r'\bclass=\\?["\']([^"\'\\]*)', raw) or [None, ""])[1].split())
        if i in covered or classes & covered_cls or re.search(r'role=\\?["\'](?:alert|status|log)|aria-live', raw):
            continue
        if tag == "button":
            skipped[i] = "단추 글자"; continue
        if i in NOT_STATUS:
            skipped[i] = NOT_STATUS[i]; continue
        cand.append(i)
    return sorted(ids), covered, cand, skipped

def selftest():
    html = '''
<div id="a1" role="alert"></div><div id="a2"></div><div id="a3"></div><button id="a4"></button><div id="a5"></div><div id="a6"></div><div id="a7"></div><div id="a8"></div><div id="a9"></div><div id="c1" class="k z"></div><div id="b1"></div>
<script>
el("a1").textContent="x"; el("a2").textContent="x"; el("a3").innerHTML="x"; el("a4").textContent="x";
document.getElementById("a5").insertAdjacentHTML("beforeend","x");
var out=document.getElementById("a6"); out.insertAdjacentHTML("beforeend","x");
var box=el("a7"); box.textContent="x"; var keep=el("a8"); keep.className="y";
var e=el("a9"); e.textContent="x"; el("c1").textContent="x";
var s=el("b1"); s.className="y";
/* 멀리 떨어진 곳 */xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
s.textContent="far";
d.querySelectorAll(".k,#a2").forEach(function(s){ s.setAttribute("aria-live","polite"); });
</script>'''
    ids, cov, cand, skipped = analyse(html)
    ok = (cand == ["a3", "a5", "a6", "a7", "a9"] and cov == {"a2"} and skipped == {"a4": "단추 글자"} and ids == ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a9", "c1"])
    if not ok:
        print(f"live-check selftest FAIL: 후보={cand} 목록={sorted(cov)} 건너뜀={skipped}", file=sys.stderr); sys.exit(1)
    print("live-check selftest PASS (role 있는 칸 · 목록에 있는 칸 · 단추 · 목록 밖 칸 · 변수 · 한 글자 이름 · 먼 곳의 같은 이름)")

def main():
    if "--selftest" in sys.argv: return selftest()
    text = APP.read_text(encoding="utf-8")
    ids, covered, cand, skipped = analyse(text)
    if "--list" in sys.argv:
        for i in ids:
            state = "낭독 목록" if i in covered else ("건너뜀: " + skipped[i] if i in skipped else ("후보" if i in cand else "role/aria-live"))
            print(f"{i:20s} {state}")
        return
    print(f"live-check: 글이 런타임에 들어오는 칸 {len(ids)}곳 — 낭독 목록 {len(covered & set(ids))} · 건너뜀 {len(skipped)} · 후보 {len(cand)}")
    for i in cand:
        print(f"::warning title=낭독 영역 밖의 칸 후보::#{i} — 글이 런타임에 들어오는데 aria-live 목록·role 에 없습니다. 상태·결과를 알리는 칸이면 낭독 영역으로, 표시 칸이면 tools/live-check.py 의 NOT_STATUS 에 이유와 함께 (#174)")
    print("(경고만입니다 — 함수 인자·객체 속성으로 쓰는 길은 못 봅니다)")

if __name__ == "__main__":
    main()
