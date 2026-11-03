#!/usr/bin/env python3
"""앱(안드로이드·iOS)에 넣을 화면을 웹앱 원본에서 다시 만듭니다.

왜 필요한가
-----------
앱에 들어가는 `index.html` 은 웹앱 `MediNote_app.html` 과 **같아야** 합니다.
2026-07 이후 두 쪽이 따로 놀아, 앱 안의 화면에는 로그인도 Supabase 연결도
없었습니다. 손으로 복사하면 또 갈라지므로 이 스크립트로 만듭니다.

무엇을 하는가
-------------
1. `MediNote_app.html` 을 읽습니다.
2. 바깥에서 받아 오던 자리(`medinote.config.js`, `vendor/*.js`)를
   **파일 안으로 옮겨 붙입니다.** 앱은 인터넷 없이 열려야 하는데,
   예전 앱 화면은 React 를 CDN 에서 받고 있어 비행기 모드에서 빈 화면이었습니다.
3. 아이콘·manifest 를 옆에 복사합니다 (콘솔 404 방지).
4. 세 곳에 같은 결과를 넣습니다.
     MediNote_apps_0706/shared/                       ← 브라우저로도 그냥 열립니다
     MediNote_apps_0706/android/app/src/main/assets/  ← APK 안에 들어갑니다
     MediNote_apps_0706/ios/MediNote/                 ← Xcode Bundle 에 넣습니다

한 파일로 합치는 이유는 안드로이드 assets 와 iOS Bundle 이 하위 폴더를
다루는 방식이 서로 달라서입니다. 합쳐 두면 어느 쪽에서도 경로가 깨지지 않습니다.

쓰는 법
-------
    python3 tools/build-packaged-app.py          만들기
    python3 tools/build-packaged-app.py --check  갈라졌는지만 보기 (고치지 않음)

`--check` 는 다시 만든 결과가 지금 파일과 다르면 1 을 돌려줍니다.
"""

import base64
import filecmp
import hashlib
import importlib.util
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "MediNote_app.html"

# 파일 안으로 옮겨 붙일 것 — 앱에서는 바깥으로 나가지 않습니다.
INLINE = [
    "medinote.config.js",
    "vendor/react-18.production.min.js",
    "vendor/react-dom-18.production.min.js",
    "vendor/supabase-js-2.umd.js",
]

# 옆에 그대로 복사할 것 — 없으면 콘솔에 404 가 뜹니다.
COPY = [
    "manifest.webmanifest",
    "apple-touch-icon.png",
    "favicon-32.png",
    "icon-192.png",
    "icon-512.png",
    "icon-512-maskable.png",
]

# 글꼴 (#51 MN-51-3) — 웹에서는 vendor/fonts/medinote-fonts.css 를 같은 출처에서 읽습니다.
# 앱 셸에서는 그 CSS 를 화면 안에 붙이고, 글꼴 파일과 라이선스는 index.html **옆에 평평하게** 둡니다.
# iOS 는 XcodeGen 이 하위 폴더를 Bundle 맨 위로 펴 넣으므로(그룹) 하위 폴더 주소가 깨집니다.
FONT_CSS = "vendor/fonts/medinote-fonts.css"
FONT_LINK = f'<link rel="stylesheet" href="{FONT_CSS}">'
FONT_FILES = [
    "vendor/fonts/Pretendard-Regular.subset.woff2",
    "vendor/fonts/Pretendard-SemiBold.subset.woff2",
    "vendor/fonts/Pretendard-Bold.subset.woff2",
    "vendor/fonts/Pretendard-ExtraBold.subset.woff2",
    "vendor/fonts/Gaegu-Regular.subset.woff2",
    "vendor/fonts/Gaegu-Bold.subset.woff2",
    "vendor/fonts/OFL-Pretendard.txt",
    "vendor/fonts/OFL-Gaegu.txt",
]

# 앱 안 「증상 신고·공유」 사본(window.__MNRP_SRC)이 읽는 것 — 셸에는 vendor/ 가 없으므로 사본 안에 붙입니다 (#90 MN-90-1)
REPORT_INLINE = [
    "medinote.config.js",
    "vendor/supabase-js-2.umd.js",
    "vendor/qrcodejs-1.0.0.min.js",
]
MNRP = re.compile(r'(window\.__MNRP_SRC=")([A-Za-z0-9+/=]*)(")')

TARGETS = [
    ROOT / "MediNote_apps_0706" / "shared",
    ROOT / "MediNote_apps_0706" / "android" / "app" / "src" / "main" / "assets",
    ROOT / "MediNote_apps_0706" / "ios" / "MediNote",
]

BANNER = (
    "<!-- 이 파일은 tools/build-packaged-app.py 가 MediNote_app.html 에서 만들었습니다.\n"
    "     여기를 직접 고치지 마세요 — 다음 실행 때 지워집니다.\n"
    "     화면을 고칠 곳은 저장소 맨 위의 MediNote_app.html 한 곳뿐입니다. -->\n"
)


def inline_script(html: str, rel: str, where: str) -> str:
    tag = f'<script src="{rel}"></script>'
    if tag not in html:
        raise SystemExit(
            f"{where} 에서 {tag} 를 찾지 못했습니다.\n"
            "원본이 바뀌었습니다. 이 스크립트의 목록을 맞춰 주세요."
        )
    body = (ROOT / rel).read_text(encoding="utf-8")
    # 본문 안의 </script> 가 태그를 일찍 닫아 버리는 것을 막습니다.
    body = body.replace("</script", "<\\/script")
    return html.replace(tag, f"<script>/* {rel} */\n{body}\n</script>", 1)


def inline_fonts(html: str, where: str) -> str:
    if FONT_LINK not in html:
        raise SystemExit(f"{where} 에서 {FONT_LINK} 를 찾지 못했습니다.")
    css = (ROOT / FONT_CSS).read_text(encoding="utf-8")
    return html.replace(FONT_LINK, f"<style>/* {FONT_CSS} — 글꼴은 index.html 옆 */\n{css}</style>", 1)


def check_report_embed() -> None:
    """앱 안 사본이 단독 파일과 같은지 — 다르면 멈춥니다 (tools/embed-report-screen.py)."""
    spec = importlib.util.spec_from_file_location("embed_report_screen", ROOT / "tools" / "embed-report-screen.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if mod.embedded(SOURCE.read_text(encoding="utf-8")) != mod.encode(mod.SRC.read_text(encoding="utf-8")):
        raise SystemExit(
            "앱 안 「증상 신고·공유」 사본이 증상신고_공유.html 과 다릅니다.\n"
            "먼저: python3 tools/embed-report-screen.py"
        )


def package_report(html: str) -> str:
    m = MNRP.search(html)
    if not m:
        raise SystemExit("MediNote_app.html 에서 window.__MNRP_SRC 를 찾지 못했습니다.")
    page = base64.b64decode(m.group(2)).decode("utf-8")
    for rel in REPORT_INLINE:
        page = inline_script(page, rel, "증상신고_공유.html")
    page = inline_fonts(page, "증상신고_공유.html")
    b64 = base64.b64encode(page.encode("utf-8")).decode("ascii")
    return html[:m.start(2)] + b64 + html[m.end(2):]


def build() -> str:
    check_report_embed()
    html = SOURCE.read_text(encoding="utf-8")
    html = package_report(html)
    html = inline_fonts(html, "MediNote_app.html")

    for rel in INLINE:
        html = inline_script(html, rel, "MediNote_app.html")

    # 서비스워커는 패키징본에서 뺍니다.
    #
    # 안드로이드 WebView·iOS WKWebView 는 이 파일을 file:// 로 엽니다. 그 origin 은
    # 'null' 이라 브라우저가 서비스워커 등록을 거부합니다(실측 확인, #16). 게다가
    # MediNote.sw.js 자체가 패키징 폴더에 없습니다. 남겨 두면 콘솔 오류만 납니다.
    #
    # 웹앱(https)에서는 그대로 돕니다 — 원본은 건드리지 않습니다.
    sw_line = ('  if("serviceWorker" in navigator){ window.addEventListener("load", '
               'function(){ navigator.serviceWorker.register("MediNote.sw.js").catch(function(){}); }); }')
    if sw_line not in html:
        raise SystemExit(
            "MediNote_app.html 에서 서비스워커 등록 줄을 찾지 못했습니다.\n"
            "원본이 바뀌었습니다. 이 스크립트의 sw_line 을 맞춰 주세요."
        )
    html = html.replace(
        sw_line,
        "  /* 서비스워커는 패키징본에서 뺐습니다 — file:// 에서는 등록이 거부됩니다 (#16) */",
        1,
    )

    # <!DOCTYPE html> 바로 뒤에 안내를 붙입니다.
    first_newline = html.index("\n") + 1
    return html[:first_newline] + BANNER + html[first_newline:]


def main() -> int:
    check_only = "--check" in sys.argv
    html = build()
    digest = hashlib.sha256(html.encode("utf-8")).hexdigest()[:12]
    drifted = []

    for target in TARGETS:
        rel_target = target.relative_to(ROOT)
        index = target / "index.html"
        if check_only:
            if not index.exists() or index.read_text(encoding="utf-8") != html:
                drifted.append(f"{rel_target}/index.html")
        else:
            target.mkdir(parents=True, exist_ok=True)
            index.write_text(html, encoding="utf-8")

        for name in COPY:
            dest = target / name
            if check_only:
                if not dest.exists() or not filecmp.cmp(ROOT / name, dest, shallow=False):
                    drifted.append(f"{rel_target}/{name}")
            else:
                shutil.copy2(ROOT / name, dest)

        for rel in FONT_FILES:
            dest = target / Path(rel).name
            if check_only:
                if not dest.exists() or not filecmp.cmp(ROOT / rel, dest, shallow=False):
                    drifted.append(f"{rel_target}/{Path(rel).name}")
            else:
                shutil.copy2(ROOT / rel, dest)

        if not check_only:
            print(f"  {rel_target}/index.html  ({len(html):,} 바이트)")

    if check_only:
        if drifted:
            print("앱 화면이 웹앱과 갈라졌습니다:")
            for path in drifted:
                print(f"  - {path}")
            print("\n고치려면: python3 tools/build-packaged-app.py")
            return 1
        print(f"앱 화면이 웹앱과 같습니다 (sha256 {digest}).")
        return 0

    print(f"\nMediNote_app.html → 앱 화면 3곳 (sha256 {digest})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
