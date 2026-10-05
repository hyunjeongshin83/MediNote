#!/usr/bin/env python3
"""React 인라인 style 이 APP-STYLE 토큰 밖으로 새는지 센다 (#74 MN-74-6).

#17 · #31 · #42 · #74 네 번 모두 같은 원인이었다 — 검사가 <style> 만 보고,
실제 첫 화면(스플래시·온보딩·홈)을 그리는 React 번들의 인라인 style 은 안 봤다.
이 검사는 React 블록(`var C = {` 가 있는 <script>)만 본다.

  fontSize: 12          px 숫자 — rem 이나 var(--fs-*) 여야 한다 (APP-STYLE 3-2-2)
  borderRadius: 16      숫자 — var(--r-*) 여야 한다 (3-4). 50% 는 그대로 둔다
  color: C.g4 · g5 · d4 · d5  흰 바탕 4.5:1 미달인 중간 톤을 글자색으로 쓰면 안 된다 (3-1)
                        g0~g3 연한 틸은 짙은 카드(brand 그라데이션) 위 글자라 세지 않는다 — 바탕을 모르는 검사라서
  letterSpacing 은 세지 않는다 — MN-74-5 가 R16 대기라 토큰이 아직 없다

쓰는 법:  python3 tools/style-check.py            0곳이면 0, 아니면 1
          python3 tools/style-check.py --selftest  일부러 넣은 보기에 걸리는지
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "MediNote_app.html"
BAD_TEXT = r"color:\s*C\.(?:g4|g5|d4|d5)\b"   # #12BDB0(2.35) · #0DA298(3.16) · #7E9497(3.20) · #C0D3CF(1.56) — 흰 바탕 기준
RULES = [
    ("fontSize px",      r"fontSize:\s*\d"),
    ("borderRadius 숫자", r"borderRadius:\s*\d"),
    ("글자색 AA 미달",    BAD_TEXT),
]

def react_block(text):
    i = text.find("  var C = {")
    if i < 0:
        return ""
    a = text.rfind("<script", 0, i); b = text.find("</script>", i)
    return text[a:b]

def check(text):
    blk = react_block(text)
    out = []
    for name, pat in RULES:
        for m in re.finditer(pat, blk):
            line = text.count("\n", 0, text.find(blk) + m.start()) + 1
            out.append((name, line, blk[max(0, m.start() - 30):m.end() + 20].replace("\n", " ")))
    return out

def main():
    if "--selftest" in sys.argv:
        src = APP.read_text(encoding="utf-8")
        assert not check(src), "지금 파일이 깨끗해야 자가검사를 할 수 있습니다"
        blk = react_block(src)
        # 띄어 쓴 꼴과 붙여 쓴 꼴(fontSize:12) 둘 다 걸려야 한다 — 콜론 뒤 공백을 요구하면 붙여 쓴 번들 편집이 새어 나간다 (PR #75 Codex P2)
        bad = src.replace(blk, blk + '\nvar __t = { fontSize: 12, borderRadius: 16, color: C.g5 };\nvar __u = {fontSize:12,borderRadius:16,color:C.g5};', 1)
        got = sorted(n for n, _, _ in check(bad))
        exp = sorted([n for n, _ in RULES] * 2)
        print("selftest", "OK" if got == exp else "FAIL", got)
        return 0 if got == exp else 1
    hits = check(APP.read_text(encoding="utf-8"))
    for name, line, ctx in hits:
        print(f"{name}: MediNote_app.html:{line}  …{ctx}…")
    print(f"style-check: React 인라인 style 토큰 밖 {len(hits)}곳")
    return 1 if hits else 0

if __name__ == "__main__":
    sys.exit(main())
