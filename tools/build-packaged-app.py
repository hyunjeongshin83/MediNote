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

import filecmp
import hashlib
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


def build() -> str:
    html = SOURCE.read_text(encoding="utf-8")

    for rel in INLINE:
        tag = f'<script src="{rel}"></script>'
        if tag not in html:
            raise SystemExit(
                f"MediNote_app.html 에서 {tag} 를 찾지 못했습니다.\n"
                "원본이 바뀌었습니다. 이 스크립트의 INLINE 목록을 맞춰 주세요."
            )
        body = (ROOT / rel).read_text(encoding="utf-8")
        # 본문 안의 </script> 가 태그를 일찍 닫아 버리는 것을 막습니다.
        body = body.replace("</script", "<\\/script")
        html = html.replace(tag, f"<script>/* {rel} */\n{body}\n</script>", 1)

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
