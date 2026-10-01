#!/usr/bin/env python3
"""사실이 아닌 문구와 사용목적을 뒤집는 낱말이 다시 들어오지 않게 — 「서버로 보내지 않습니다」·「기기를 떠나지 않습니다」 (#49 MN-49-1) · 「부작용 모니터링」 등 (#57 MN-57-2)

CLAUDE.md §3 이 쓰지 말라고 한 두 문장이 09-19 뒤 네 번(MN-33-1 · MN-33-3 · MN-47-4 · VaccineNote VN-65-1) 따로
고쳐졌습니다. 자리마다 고치는 대신 종류로 막습니다 — 이 검사가 CI(안드로이드 APK 작업)에서 돕니다.

    python3 tools/phrase-check.py            걸리면 1, 자리마다 한 줄
    python3 tools/phrase-check.py --list     검사 대상 파일만 보여 줌

빼는 것: CLAUDE.md(규칙 자체를 인용) · docs/FIXES.md(이슈에서 만든 표) · node_modules · 앱 화면 3벌(index.html 은 MediNote_app.html 의 사본)
한 줄만 예외로 두려면 그 줄에 phrase-ok 를 적습니다 (예: 「…라고 쓰지 마세요」처럼 인용할 때).
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PHRASES = [
    (re.compile(r"서버로\s*보내지\s*않"), "「서버로 보내지 않습니다」 — 심박·증상·프로필은 사용자가 누르면 서버로 갑니다 (CLAUDE.md §3)"),
    (re.compile(r"기기를\s*떠나지\s*않"), "「기기를 떠나지 않습니다」 — 사실이 아닙니다 (CLAUDE.md §3)"),
]
# 사용목적을 뒤집는 낱말 — 식약처는 코드가 아니라 표시된 사용목적으로 의료기기를 가립니다 (#15 · docs/STORE-LISTING.md · #57 MN-57-2).
# 한 줄만 써도 판정이 바뀌는 여러 낱말 묶음은 걸리면 1, 홑낱말(진단·판정·치료·처방…)은 스토어 문구 파일에서만 「주의」로 보여 줍니다.
STORE_FAIL = [
    (re.compile(r"부작용\s*모니터링"), "「부작용 모니터링」 — 의료기기 사용목적 (식약처 지침서-0091-03 · #15)"),
    (re.compile(r"위험\s*알람|위험\s*경보"), "「위험 알람」 — 의료기기 사용목적 (#15)"),
    (re.compile(r"비침습\s*연속\s*측정"), "「비침습 연속 측정」 — FDA 승인 분석물 0개 · 쓰지 않습니다 (#15)"),
    (re.compile(r"\bMARD\b"), "「MARD」 — 21 CFR 862.1355 에 없는 지표 (#15)"),
    (re.compile(r"임상\s*검증|정확하게\s*측정|이상\s*감지"), "「임상 검증 · 정확하게 측정 · 이상 감지」 — 의료기기 사용목적으로 읽힙니다 (STORE-LISTING)"),
]
STORE_WARN = re.compile(r"진단|판정|판독|치료|처방|예측|응급|경보|정확도|정밀|의료기기")
STORE_FILES = {"docs/STORE-LISTING.md", "README.md", "HEALTH_SETUP.md", "PRIVACY.md",
               "MediNote_apps_0706/android/app/src/main/res/values/strings.xml", "MediNote_apps_0706/ios/project.yml"}
EXT = {".md", ".html", ".js", ".ts", ".kt", ".swift", ".txt", ".json", ".webmanifest", ".xml", ".yml"}
SKIP_DIRS = {"node_modules", ".git", ".github", ".gradle", "build"}   # .github: 워크플로가 규칙 문구를 인용함
SKIP_FILES = {"CLAUDE.md", "docs/FIXES.md"}
SKIP_GLOB = ("MediNote_apps_0706/shared/index.html", "MediNote_apps_0706/android/app/src/main/assets/index.html", "MediNote_apps_0706/ios/MediNote/index.html")

def files():
    for p in ROOT.rglob("*"):
        if not p.is_file() or p.suffix not in EXT: continue
        rel = p.relative_to(ROOT).as_posix()
        if any(part in SKIP_DIRS for part in p.parts): continue
        if rel in SKIP_FILES or rel in SKIP_GLOB: continue
        yield p, rel

def main():
    if "--list" in sys.argv:
        for _, rel in files(): print(rel)
        return 0
    hits = 0; warns = 0
    for p, rel in files():
        try: text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError: continue
        for n, line in enumerate(text.splitlines(), 1):
            if "phrase-ok" in line: continue
            for rx, why in PHRASES + STORE_FAIL:
                if rx.search(line):
                    hits += 1
                    print(f"{rel}:{n}: {why}")
            if rel in STORE_FILES and STORE_WARN.search(line):
                warns += 1
                print(f"주의 {rel}:{n}: 「{STORE_WARN.search(line).group(0)}」 — 스토어 문구에서는 부정문이라도 다시 읽어 보세요 (STORE-LISTING)")
    if warns:
        print(f"주의 {warns}곳 (걸림 아님 · 올리기 전에 눈으로)")
    if hits:
        print(f"\n사실이 아닌 문구 {hits}곳. 자리마다 고치지 말고 CLAUDE.md §3 대로 사실을 적으세요.", file=sys.stderr)
        return 1
    print("phrase-check: 사실이 아닌 문구 0곳")
    return 0

if __name__ == "__main__":
    sys.exit(main())
