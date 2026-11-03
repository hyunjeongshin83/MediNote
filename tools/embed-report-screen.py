#!/usr/bin/env python3
"""앱 안 「증상 신고·공유」 화면을 단독 파일에서 다시 박습니다 (#90 MN-90-1)

왜 필요한가
-----------
`MediNote_app.html` 은 `증상신고_공유.html` 을 base64 로 박아 둔 사본(`window.__MNRP_SRC`)을 iframe(srcdoc)으로 엽니다.
손으로 박은 사본이 단독 파일과 갈라져, 앱 안에서는 낡은 글자 크기·옛 저장 길(hub_state 직접)·개인 키로 Anthropic 을 직접
부르는 코드가 남아 있었습니다(#90 · #130). base64 안은 어느 검사도 못 보므로 이 스크립트로만 만듭니다.

    python3 tools/embed-report-screen.py          다시 박기
    python3 tools/embed-report-screen.py --check  갈라졌는지만 보기 (다르면 1)

사본은 단독 파일 그대로입니다. srcdoc 문서는 부모(MediNote_app.html)의 주소를 기준으로 상대 주소를 풀므로,
웹에서는 vendor/ · medinote.config.js 를 같은 출처에서 읽습니다. 앱 셸 사본(index.html 3벌)에서는
tools/build-packaged-app.py 가 그 상대 주소들을 사본 안에 붙입니다.
"""
import base64, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "MediNote_app.html"
SRC = ROOT / "증상신고_공유.html"
PAT = re.compile(r'(window\.__MNRP_SRC=")([A-Za-z0-9+/=]*)(")')


def encode(text: str) -> str:
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


def decode(b64: str) -> str:
    return base64.b64decode(b64).decode("utf-8")


def embedded(html: str) -> str:
    m = PAT.search(html)
    if not m:
        raise SystemExit("MediNote_app.html 에서 window.__MNRP_SRC=\"…\" 를 찾지 못했습니다.")
    return m.group(2)


def main() -> int:
    html = APP.read_text(encoding="utf-8")
    want = encode(SRC.read_text(encoding="utf-8"))
    if "--check" in sys.argv:
        if embedded(html) != want:
            print("앱 안 「증상 신고·공유」 사본이 증상신고_공유.html 과 다릅니다.\n고치려면: python3 tools/embed-report-screen.py")
            return 1
        print("앱 안 「증상 신고·공유」 사본이 단독 파일과 같습니다.")
        return 0
    embedded(html)
    new = PAT.sub(lambda m: m.group(1) + want + m.group(3), html, count=1)
    if new != html:
        APP.write_text(new, encoding="utf-8")
        print("증상신고_공유.html → MediNote_app.html (window.__MNRP_SRC) 다시 박음")
    else:
        print("이미 같습니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
