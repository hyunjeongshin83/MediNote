#!/usr/bin/env python3
"""이슈에 적힌 「고칠 것」을 읽어 냅니다.

왜 있나
-------
조사하는 쪽(예약 리서치)과 고치는 쪽(Claude Code)이 다릅니다. 사이에 사람이 없어서,
읽는 쪽이 기계적으로 집어낼 수 있어야 합니다. 형식은 docs/FIX-FORMAT.md 에 있습니다.

    ```fix
    id:     MN-14-3
    파일:   …
    막는것: 없음
    상태:   대기
    ```

쓰는 법
-------
    python3 tools/fixes.py              사람이 읽는 표
    python3 tools/fixes.py --todo       막는 것 없고 아직 대기인 것만 (반영 대상)
    python3 tools/fixes.py --json       기계가 읽는 목록
    python3 tools/fixes.py --report     docs/FIXES.md 를 다시 만듭니다

    --repo owner/name   다른 저장소 (기본값은 이 저장소)
    --from  issues.json GitHub API 응답을 미리 받아 둔 파일에서 읽습니다

이슈를 직접 받아 오려면 GITHUB_TOKEN 이 필요합니다. 없으면 --from 을 쓰거나,
저장소에 들어 있는 docs/FIXES.md 를 읽으십시오.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_REPO = 'hyunjeongshin83/MediNote'

KEYS = ['id', '파일', '무엇', '어떻게', '확인', '막는것', '상태']
BLOCK = re.compile(r'```fix[ \t]*\n(.*?)```', re.S)


def parse_blocks(body, issue_no, issue_title):
    """이슈 본문에서 fix 칸을 꺼냅니다. 칸 밖의 글은 무시합니다."""
    out = []
    for m in BLOCK.finditer(body or ''):
        item = {'이슈': issue_no, '제목': issue_title}
        for line in m.group(1).splitlines():
            line = line.strip()
            if not line or ':' not in line:
                continue
            k, v = line.split(':', 1)
            k, v = k.strip(), v.strip()
            if k in KEYS:
                item[k] = v
        if 'id' in item:
            out.append(item)
        else:
            # id 가 없으면 중복 반영을 막을 수 없으므로 세지 않고 알립니다
            print('⚠ 이슈 #%s 의 fix 칸에 id 가 없습니다 — 건너뜁니다' % issue_no,
                  file=sys.stderr)
    return out


def todo(item):
    """사람 확인 없이 지금 반영해도 되는 항목인가."""
    blocked = item.get('막는것', '').strip()
    state = item.get('상태', '').strip()
    return blocked in ('없음', '') and state.startswith('대기')


def _get(url, token):
    req = urllib.request.Request(url, headers={
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ' + token,
        'User-Agent': 'fixes.py',
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def fetch(repo, token):
    """열려 있는 이슈와 그 댓글을 함께 받아 옵니다.

    fix 칸은 이슈 본문에 두는 것이 원칙이지만, 이미 올라간 이슈에 나중에 붙일 때는
    댓글로도 답니다. 본문을 고쳐 쓰면 조사한 사람이 적은 글이 바뀌기 때문입니다.
    """
    out = _get('https://api.github.com/repos/%s/issues?state=open&per_page=100' % repo, token)
    for iss in out:
        if 'pull_request' in iss:
            continue
        if not iss.get('comments'):
            continue
        try:
            cs = _get('https://api.github.com/repos/%s/issues/%s/comments'
                      % (repo, iss['number']), token)
            iss['_comments'] = [c.get('body') or '' for c in cs]
        except urllib.error.HTTPError:
            iss['_comments'] = []
    return out


def collect(repo, from_file):
    if from_file:
        raw = json.loads(Path(from_file).read_text(encoding='utf-8'))
    else:
        token = os.environ.get('GITHUB_TOKEN') or os.environ.get('GH_TOKEN')
        if not token:
            sys.exit('GITHUB_TOKEN 이 없습니다. --from 으로 미리 받아 둔 파일을 주거나,\n'
                     'docs/FIXES.md 를 읽으십시오.')
        try:
            raw = fetch(repo, token)
        except urllib.error.HTTPError as e:
            sys.exit('이슈를 받지 못했습니다 (%s). 토큰 권한을 확인하십시오.' % e.code)

    items = []
    for iss in raw:
        if 'pull_request' in iss:        # PR 은 이슈 목록에 섞여 옵니다
            continue
        text = iss.get('body') or ''
        for c in iss.get('_comments', []):
            text += '\n\n' + c
        items.append(parse_blocks(text, iss.get('number'), iss.get('title', '')))

    flat = [x for group in items for x in group]

    # 같은 id 가 두 번 나오면 뒤엣것을 씁니다 — 댓글로 고쳐 단 것이 본문보다 새것입니다
    seen = {}
    for x in flat:
        seen[x['id']] = x
    return list(seen.values())


def table(items):
    if not items:
        return '  없음\n'
    w = max(len(x.get('id', '')) for x in items)
    lines = []
    for x in items:
        mark = '→' if todo(x) else ' '
        lines.append('  %s %-*s  #%-3s %s' % (
            mark, w, x.get('id', '?'), x.get('이슈', '?'), x.get('파일', '')))
        lines.append('     %s' % x.get('무엇', ''))
        if not todo(x):
            why = x.get('막는것', '').strip()
            st = x.get('상태', '').strip()
            lines.append('     ⏸ %s' % (why if why not in ('없음', '') else st))
        lines.append('')
    return '\n'.join(lines)


def report(items, repo):
    t = [x for x in items if todo(x)]
    blocked = [x for x in items if not todo(x) and x.get('상태', '').startswith('대기')]
    done = [x for x in items if x.get('상태', '').startswith('반영됨')]
    held = [x for x in items if x.get('상태', '').startswith('보류')]

    L = []
    A = L.append
    A('# 고칠 것 — 지금 상태')
    A('')
    A('`tools/fixes.py --report` 가 만든 것입니다. **손으로 고치지 마세요** —')
    A('고칠 것은 이슈 본문의 `fix` 칸입니다 (형식은 `docs/FIX-FORMAT.md`).')
    A('')
    A('```')
    A('저장소       %s' % repo)
    A('바로 반영    %d 건' % len(t))
    A('사람 대기    %d 건' % len(blocked))
    A('반영됨       %d 건' % len(done))
    A('보류         %d 건' % len(held))
    A('```')
    A('')

    A('## 바로 반영해도 되는 것')
    A('')
    A('`막는것: 없음` 이고 아직 `대기` 인 것입니다. **사람 확인 없이 고쳐도 됩니다.**')
    A('')
    if t:
        for x in t:
            A('### `%s` — 이슈 #%s' % (x.get('id'), x.get('이슈')))
            A('')
            A('| | |')
            A('|---|---|')
            A('| 파일 | `%s` |' % x.get('파일', ''))
            A('| 무엇 | %s |' % x.get('무엇', ''))
            A('| 어떻게 | %s |' % x.get('어떻게', ''))
            A('| 확인 | %s |' % x.get('확인', ''))
            A('')
    else:
        A('없습니다.')
        A('')

    A('## 사람이 정해야 넘어가는 것')
    A('')
    if blocked:
        A('| id | 이슈 | 무엇 | 막는 것 |')
        A('|---|---|---|---|')
        for x in blocked:
            A('| `%s` | #%s | %s | **%s** |' % (
                x.get('id'), x.get('이슈'), x.get('무엇', ''), x.get('막는것', '')))
    else:
        A('없습니다.')
    A('')

    if done:
        A('## 이미 반영된 것')
        A('')
        A('| id | 이슈 | 무엇 | 커밋 |')
        A('|---|---|---|---|')
        for x in done:
            st = x.get('상태', '')
            commit = st.split('·', 1)[1].strip() if '·' in st else ''
            A('| `%s` | #%s | %s | `%s` |' % (
                x.get('id'), x.get('이슈'), x.get('무엇', ''), commit))
        A('')

    if held:
        A('## 보류')
        A('')
        A('| id | 이슈 | 까닭 |')
        A('|---|---|---|')
        for x in held:
            A('| `%s` | #%s | %s |' % (x.get('id'), x.get('이슈'), x.get('상태', '')))
        A('')

    A('---')
    A('')
    A('반영한 뒤에는 **이슈의 `fix` 칸에서 `상태` 를 `반영됨 · <커밋>` 으로 바꾸고**,')
    A('이 파일을 `--report` 로 다시 만들어 주세요. 그래야 다음에 또 고치지 않습니다.')
    return '\n'.join(L) + '\n'


def main():
    p = argparse.ArgumentParser(description='이슈의 「고칠 것」을 읽어 냅니다')
    p.add_argument('--repo', default=DEFAULT_REPO)
    p.add_argument('--from', dest='from_file', help='미리 받아 둔 이슈 JSON')
    p.add_argument('--todo', action='store_true', help='바로 반영할 것만')
    p.add_argument('--json', action='store_true')
    p.add_argument('--report', action='store_true', help='docs/FIXES.md 를 다시 만듭니다')
    a = p.parse_args()

    items = collect(a.repo, a.from_file)

    if a.report:
        out = ROOT / 'docs' / 'FIXES.md'
        out.parent.mkdir(exist_ok=True)
        out.write_text(report(items, a.repo), encoding='utf-8')
        print('%s — 전체 %d · 바로 반영 %d' % (out, len(items), len([x for x in items if todo(x)])))
        return

    if a.todo:
        items = [x for x in items if todo(x)]

    if a.json:
        print(json.dumps(items, ensure_ascii=False, indent=2))
        return

    print('\n%s · 고칠 것 %d 건 (→ 는 바로 반영 가능)\n' % (a.repo, len(items)))
    print(table(items))


if __name__ == '__main__':
    main()
