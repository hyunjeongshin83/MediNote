#!/bin/bash
# 세션이 열릴 때 밀린 것을 먼저 보여 줍니다.
#
# 조사하는 쪽(예약 리서치)이 이슈에 「고칠 것」을 fix 칸으로 적어 두고,
# 고치는 쪽(이 세션)이 그것을 읽어 반영합니다. 사이에 사람이 없습니다.
# 그래서 세션이 열리자마자 무엇이 밀려 있는지 눈앞에 둡니다.
#
# 규칙은 CLAUDE.md 1절과 docs/FIX-FORMAT.md 에 있습니다.
#   「바로 반영해도 되는 것」(막는것 없음 · 대기)만 확인 없이 고칩니다.
#   「사람이 정해야 넘어가는 것」은 손대지 않습니다.
set -uo pipefail

# 웹(원격) 세션에서만 돕니다. 로컬에서는 조용히 빠집니다.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -f tools/fixes.py ] || exit 0

echo "## 세션 시작 — 밀린 것"
echo

# 이슈에서 직접 읽습니다. 못 닿으면 저장소의 docs/FIXES.md 로 대신합니다.
python3 - <<'PY' 2>/dev/null
import sys, re
sys.path.insert(0, 'tools')
import fixes
try:
    items = fixes.collect(fixes.DEFAULT_REPO, None)
except SystemExit:
    sys.exit(3)
todo = [x for x in items if fixes.todo(x)]
wait = [x for x in items if not fixes.todo(x) and x.get('상태','').startswith('대기')]
done = [x for x in items if x.get('상태','').startswith('반영됨')]
print('이슈에서 방금 읽었습니다 (%s).' % fixes.DEFAULT_REPO)
print()
print('```')
print('바로 반영    %d 건   ← 확인 없이 고칩니다' % len(todo))
print('사람 대기    %d 건   ← 손대지 않습니다 (docs/FIXES.md 에 막는 것이 적혀 있습니다)' % len(wait))
print('반영됨       %d 건' % len(done))
print('```')
if todo:
    print()
    print('### 바로 반영해도 되는 것')
    print()
    for x in todo:
        print('- `%s` #%s · `%s`' % (x['id'], x.get('이슈'), x.get('파일','')))
        print('  무엇: %s' % x.get('무엇',''))
        print('  어떻게: %s' % x.get('어떻게',''))
        print('  확인: %s' % x.get('확인',''))
PY
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "이슈에 못 닿아 저장소의 docs/FIXES.md 를 씁니다 (마지막 --report 시점 기준)."
  echo
  echo '```'
  sed -n '/^```$/,/^```$/p' docs/FIXES.md | sed '1d;$d'
  echo '```'
  echo
  echo '「바로 반영해도 되는 것」 절은 docs/FIXES.md 에서 직접 보세요.'
fi

echo
echo "→ 바로 반영할 것이 있으면 CLAUDE.md 1절대로 고치고, 그 이슈의 fix 칸에서 상태를"
echo "  \`반영됨 · <커밋>\` 으로 바꾸고, \`python3 tools/fixes.py --report\` 를 다시 만들어 함께 커밋하세요."
echo "→ 없으면 손대지 마세요. 사용자가 시킨 일부터 하세요."
